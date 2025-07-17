//
//  MenuBarItemSourceCache.swift
//  MenuBarItemService
//

import AXSwift
import Cocoa
import Combine
import os.lock

enum AXHelpers {
    private static let queue = DispatchQueue.queue(
        label: "AXHelpers.queue",
        qos: .utility,
        attributes: .concurrent
    )

    static func application(for runningApp: NSRunningApplication) -> Application? {
        queue.sync { Application(runningApp) }
    }

    static func extrasMenuBar(for app: Application) throws -> UIElement? {
        #warning("Make this throw and see if it's faster with the check below")
        queue.sync { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        queue.sync { try? element.arrayAttribute(.children) } ?? []
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        queue.sync { try? element.attribute(.enabled) } == true
    }

    static func frame(for element: UIElement) -> CGRect? {
        queue.sync { try? element.attribute(.frame) }
    }
}

// MARK: - MenuBarItemSourceCache

enum MenuBarItemSourceCache {
    private static let concurrentWorkQueue = DispatchQueue.queue(
        label: "MenuBarItemSourceCache.concurrentWorkQueue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    private final class CachedApplication: Sendable {
        private enum ExtrasMenuBarState: @unchecked Sendable {
            case uninitialized
            case initialized(UIElement?)

            var isInitialized: Bool {
                switch self {
                case .uninitialized: false
                case .initialized: true
                }
            }

            var extrasMenuBar: UIElement? {
                switch self {
                case .uninitialized: nil
                case .initialized(let element): element
                }
            }

            mutating func initialize(to element: UIElement?) {
                self = .initialized(element)
            }
        }

        private let runningApp: NSRunningApplication
        private let state = OSAllocatedUnfairLock<ExtrasMenuBarState>(initialState: .uninitialized)

        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        var isValidForAccessibility: Bool {
            // These checks help prevent blocking that can occur when
            // calling AX APIs while the app is an invalid state.
            runningApp.isFinishedLaunching &&
            !runningApp.isTerminated &&
            runningApp.activationPolicy != .prohibited &&
            !runningApp.isUnresponsive
        }

        var isInitialized: Bool {
            state.withLock { $0.isInitialized }
        }

        var hasExtrasMenuBar: Bool {
            state.withLock { $0.extrasMenuBar != nil }
        }

        private func initializeExtrasMenuBar() {
            guard
                !isInitialized,
                isValidForAccessibility,
                let app = AXHelpers.application(for: runningApp)
            else {
                return
            }
            do {
                if let bar = try AXHelpers.extrasMenuBar(for: app) {
                    state.withLock { $0.initialize(to: bar) }
                }
            } catch {
                state.withLock { $0.initialize(to: nil) }
            }
        }

        var extrasMenuBar: UIElement? {
            initializeExtrasMenuBar()
            return state.withLock { $0.extrasMenuBar }
        }

        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
        }
    }

    private struct State: Sendable {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        private mutating func getStableWindowBounds(for window: WindowInfo) -> CGRect? {
            let windowID = window.windowID
            var windowBounds = window.bounds

            while true {
                guard let currentBounds = Bridging.getWindowBounds(for: windowID) else {
                    pids.removeValue(forKey: windowID)
                    return nil
                }
                if windowBounds != currentBounds {
                    windowBounds = currentBounds
                } else {
                    break
                }
            }

            return windowBounds
        }

        private mutating func updateCachedPID(for window: WindowInfo, in apps: [CachedApplication]) -> Bool {
            guard let windowBounds = getStableWindowBounds(for: window) else {
                return false
            }

            for app in apps {
                // Since we're running concurrently, we could have a pid
                // at any point.
                if pids[window.windowID] != nil {
                    return true
                }

                guard let bar = app.extrasMenuBar else {
                    continue
                }

                for child in AXHelpers.children(for: bar) {
                    if pids[window.windowID] != nil {
                        return true
                    }

                    guard
                        AXHelpers.isEnabled(child),
                        let childFrame = AXHelpers.frame(for: child),
                        childFrame.center.distance(to: windowBounds.center) <= 10
                    else {
                        continue
                    }

                    pids[window.windowID] = app.processIdentifier
                    return true
                }
            }

            return false
        }

        /// Returns an array of groups formed from the current apps that meet the
        /// necessary criteria for iteration.
        ///
        /// The criteria for each group is as follows:
        ///
        /// - Group 1 (Index 0): Apps that are confirmed to have an extras menu bar.
        /// - Group 2 (Index 1): Apps that have not yet been initialized (may or may
        ///   not have an extras menu bar).
        ///
        /// Apps that don't meet the criteria for either group (a.k.a. apps that are
        /// confirmed _not_ to have an extras menu bar) are excluded for efficiency.
        private func createIterableAppGroups() -> [[CachedApplication]] {
            var groups = [[CachedApplication]](repeating: [], count: 3)

            for app in apps {
                if app.hasExtrasMenuBar {
                    groups[0].append(app)
                } else if !app.isInitialized {
                    if app.isValidForAccessibility {
                        groups[1].append(app)
                    } else {
                        groups[2].append(app)
                    }
                }
            }

            return groups
        }

        mutating func updateCachedPID(for window: WindowInfo) {
            for group in createIterableAppGroups() {
                guard updateCachedPID(for: window, in: group) else {
                    continue
                }
                return
            }
        }
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static var cancellable: AnyCancellable?

    static func start() {
        cancellable = NSWorkspace.shared.publisher(for: \.runningApplications).sink { runningApps in
            guard checkIsProcessTrusted(prompt: false) else {
                return
            }

            state.withLock { state in
                let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)

                // Convert the cached state to dictionaries keyed by pid to
                // allow for efficient repeated access.
                let appMappings = state.apps.reduce(into: [:]) { result, app in
                    result[app.processIdentifier] = app
                }
                let pidMappings: [pid_t: [CGWindowID: pid_t]] = windowIDs.reduce(into: [:]) { result, windowID in
                    if let pid = state.pids[windowID] {
                        result[pid, default: [:]][windowID] = pid
                    }
                }

                // Create a new state that matches the current running apps.
                state = runningApps.reduce(into: State()) { result, app in
                    let pid = app.processIdentifier

                    if let app = appMappings[pid] {
                        // Prefer the cached app, as it may have already done
                        // the work to initialize its extras menu bar.
                        result.apps.append(app)
                    } else {
                        // App wasn't in the cache, so it must be new.
                        result.apps.append(CachedApplication(app))
                    }

                    if let pids = pidMappings[pid] {
                        result.pids.merge(pids) { (_, new) in new }
                    }
                }
            }
        }
    }

    static func getCachedPID(for window: WindowInfo) -> pid_t? {
        concurrentWorkQueue.sync {
            state.withLock { state in
                if let pid = state.pids[window.windowID] {
                    return pid
                }
                state.updateCachedPID(for: window)
                return state.pids[window.windowID]
            }
        }
    }
}

// MARK: - CGPoint Extension

private extension CGPoint {
    /// Returns the distance between this point and another point.
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

// MARK: - CGRect Extension

private extension CGRect {
    /// The center point of the rectangle.
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

// MARK: - NSRunningApplication Extension

private extension NSRunningApplication {
    /// A Boolean value that indicates whether the application's
    /// process is unresponsive.
    var isUnresponsive: Bool {
        Bridging.isProcessUnresponsive(processIdentifier)
    }
}
