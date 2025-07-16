//
//  MenuBarItemSourceCache.swift
//  MenuBarItemService
//

import AXSwift
import Cocoa
import Combine
import os.lock

// MARK: - MenuBarItemSourceCache

enum MenuBarItemSourceCache {
//    private static let axQueue = DispatchQueue.queue(
//        label: "MenuBarItemSourceCache.axQueue",
//        qos: .utility,
//        attributes: .concurrent
//    )
//    private static let serialWorkQueue = DispatchQueue(
//        label: "MenuBarItemSourceCache.serialWorkQueue",
//        qos: .userInteractive
//    )
//    private static let concurrentWorkQueue = DispatchQueue(
//        label: "MenuBarItemSourceCache.concurrentWorkQueue",
//        qos: .userInteractive,
//        attributes: .concurrent
//    )

    private final class CachedApplication: Sendable {
        private struct ExtrasMenuBarLazyStorage: @unchecked Sendable {
            var extrasMenuBar: UIElement?
            var hasInitialized = false
        }

        private let runningApp: NSRunningApplication
        private let extrasMenuBarState = OSAllocatedUnfairLock(initialState: ExtrasMenuBarLazyStorage())

        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        var extrasMenuBar: UIElement? {
            extrasMenuBarState.withLock { storage in
                if storage.hasInitialized {
                    return storage.extrasMenuBar
                }

                // These checks help prevent blocking that can occur when
                // calling AX APIs (app could be unresponsive, or in some
                // other invalid state).
                guard
                    // !Bridging.isProcessUnresponsive(processIdentifier),
                    runningApp.isFinishedLaunching,
                    !runningApp.isTerminated,
                    runningApp.activationPolicy != .prohibited
                else {
                    return nil
                }

                defer {
                    storage.hasInitialized = true
                }

                guard let app = Application(runningApp) else {
                    print("NO APP")
                    return nil
                }

                guard let bar: UIElement? = try? app.attribute(.extrasMenuBar) else {
                    print("NO EXTRASMENUBAR")
                    return nil
                }

                storage.extrasMenuBar = bar
                return bar
            }
        }

        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
        }
    }

    private struct State: Sendable {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        mutating func updateCachedPID(for window: WindowInfo) {
            let windowID = window.windowID

            for app in apps {
                // Since we're running concurrently, we could have a pid
                // at any point.
                if pids[windowID] != nil {
                    return
                }

                guard let bar = app.extrasMenuBar else {
                    print("NO BAR")
                    continue
                }

                for child in bar.children {
                    if pids[windowID] != nil {
                        return
                    }

                    // Item window may have moved. Get the current bounds.
                    guard let windowBounds = Bridging.getWindowBounds(for: windowID) else {
                        print("NO BOUNDS BRIDGED")
                        pids.removeValue(forKey: windowID)
                        return
                    }

                    guard windowBounds == window.bounds else {
                        print("NO MATCH")
                        return
                    }

                    guard
                        let childFrame = child.frame,
                        childFrame.center.distance(to: windowBounds.center) <= 10
                    else {
                        continue
                    }

                    print("HAS PID:", windowID, app.processIdentifier)
                    pids[windowID] = app.processIdentifier
                    return
                }
            }
        }
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static var cancellable: AnyCancellable?

    static func start() {
        cancellable = NSWorkspace.shared.publisher(for: \.runningApplications)
            .receive(on: RunLoop.current)
            .sink { runningApps in
                print("INSIDE")
                guard checkIsProcessTrusted(prompt: false) else {
                    print("NOT TRUSTED")
                    return
                }

                state.withLock { state in
                    // Convert the cached state to dictionaries keyed by pid to
                    // allow for efficient repeated access.
                    let appMappings = state.apps.reduce(into: [:]) { result, app in
                        result[app.processIdentifier] = app
                    }
                    let pidMappings = state.pids.reduce(into: [:]) { result, pair in
                        result[pair.value, default: []].append(pair)
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

//                let windows = WindowInfo.createMenuBarWindows(option: .itemsOnly)
//                if windows.isEmpty {
//                    print("EMPTY WINDOWS")
//                }
//
//                for window in windows {
//                    print("IS WINDOW")
//                    state.withLock { state in
//                        state.updateCachedPID(for: window)
//                    }
//                }
            }
    }

    static func getCachedPID(for window: WindowInfo) -> pid_t? {
        state.withLock { state in
            if let pid = state.pids[window.windowID] {
                return pid
            }
            state.updateCachedPID(for: window)
            return state.pids[window.windowID]
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

// MARK: - DispatchQueue Extension

private extension DispatchQueue {
    /// Creates and returns a new dispatch queue that targets the global
    /// system queue with the specified quality-of-service class.
    static func queue(
        label: String,
        qos: DispatchQoS.QoSClass,
        attributes: Attributes = []
    ) -> DispatchQueue {
        let target: DispatchQueue = .global(qos: qos)
        return DispatchQueue(label: label, attributes: attributes, target: target)
    }
}

// MARK: - UIElement Extension

private extension UIElement {
    /// The element's frame.
    var frame: CGRect? {
        try? attribute(.frame)
    }

    /// The element's child elements.
    var children: [UIElement] {
        (try? arrayAttribute(.children)) ?? []
    }
}
