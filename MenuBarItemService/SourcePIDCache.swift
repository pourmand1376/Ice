//
//  SourcePIDCache.swift
//  MenuBarItemService
//

import AXSwift
import Cocoa
import Combine
import os.lock

enum SourcePIDCache {
    private static let concurrentQueue = DispatchQueue.globalTargetingQueue(
        label: "SourceCache.concurrentQueue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    private final class CachedApplication {
        private let runningApp: NSRunningApplication
        private var extrasMenuBar: UIElement?

        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        var hasExtrasMenuBar: Bool {
            extrasMenuBar != nil
        }

        var isValidForAccessibility: Bool {
            // These checks help prevent blocking that can occur when
            // calling AX APIs while the app is an invalid state.
            runningApp.isFinishedLaunching &&
            !runningApp.isTerminated &&
            runningApp.activationPolicy != .prohibited &&
            !Bridging.isProcessUnresponsive(processIdentifier)
        }

        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
        }

        func getOrCreateExtrasMenuBar() -> UIElement? {
            if let extrasMenuBar {
                return extrasMenuBar
            }
            guard
                isValidForAccessibility,
                let app = AXHelpers.application(for: runningApp),
                let bar = AXHelpers.extrasMenuBar(for: app)
            else {
                return nil
            }
            extrasMenuBar = bar
            return bar
        }
    }

    private struct State {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        /// Returns the latest bounds of the given window after ensuring
        /// that the bounds are stable (a.k.a. not currently changing).
        ///
        /// This method blocks until stable bounds can be determined, or
        /// until retrieving the bounds for the window fails.
        private func stableBounds(for window: WindowInfo) -> CGRect? {
            var cachedBounds = window.bounds

            for n in 1...5 {
                guard let latestBounds = window.getLatestBounds() else {
                    // Failure here means the window probably doesn't
                    // exist anymore.
                    return nil
                }
                if latestBounds == cachedBounds {
                    return latestBounds
                }
                cachedBounds = latestBounds
                // Sleep interval increases with each attempt.
                Thread.sleep(forTimeInterval: TimeInterval(n) / 100)
            }

            return nil
        }

        /// Reorders the cached apps so that those that are confirmed
        /// to have an extras menu bar are first in the array.
        private mutating func partitionApps() {
            var lhs = [CachedApplication]()
            var rhs = [CachedApplication]()

            for app in apps {
                if app.hasExtrasMenuBar {
                    lhs.append(app)
                } else {
                    rhs.append(app)
                }
            }

            apps = lhs + rhs
        }

        mutating func updateCachedPID(for window: WindowInfo) {
            guard
                AXHelpers.isProcessTrusted(),
                let windowBounds = stableBounds(for: window)
            else {
                return
            }

            partitionApps()

            for app in apps {
                guard let bar = app.getOrCreateExtrasMenuBar() else {
                    continue
                }
                for child in AXHelpers.children(for: bar) {
                    guard AXHelpers.isEnabled(child) else {
                        continue
                    }
                    guard
                        let childFrame = AXHelpers.frame(for: child),
                        childFrame.center.distance(to: windowBounds.center) <= 1
                    else {
                        continue
                    }
                    pids[window.windowID] = app.processIdentifier
                    return
                }
            }
        }
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static var cancellable: AnyCancellable?

    static func start() {
        cancellable = NSWorkspace.shared.publisher(for: \.runningApplications).sink { runningApps in
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

    /// Returns the cached pid for the given window, updating the
    /// cache if needed.
    static func pid(for window: WindowInfo) -> pid_t? {
        concurrentQueue.sync {
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

// MARK: - WindowInfo Extension

private extension WindowInfo {
    /// Returns the latest bounds of the window.
    func getLatestBounds() -> CGRect? {
        Bridging.getWindowBounds(for: windowID)
    }
}
