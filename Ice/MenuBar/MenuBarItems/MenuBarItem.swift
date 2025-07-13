//
//  MenuBarItem.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine

// MARK: - MenuBarItem

/// A representation of an item in the menu bar.
struct MenuBarItem: CustomStringConvertible {
    /// The tag associated with this item.
    let tag: MenuBarItemTag

    /// The item's window identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the item.
    let ownerPID: pid_t

    /// The identifier of the process that created the item.
    let sourcePID: pid_t?

    /// The item's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The item's window title.
    let title: String?

    /// The name of the process that owns the item.
    ///
    /// This may have a value when ``owningApplication`` does not have
    /// a localized name.
    let ownerName: String?

    /// A Boolean value that indicates whether the item is on screen.
    let isOnScreen: Bool

    /// A Boolean value that indicates whether the item can be moved.
    var isMovable: Bool {
        tag.isMovable
    }

    /// A Boolean value that indicates whether the item can be hidden.
    var canBeHidden: Bool {
        tag.canBeHidden
    }

    /// A Boolean value that indicates whether the item is one of Ice's
    /// control items.
    var isControlItem: Bool {
        tag.isControlItem
    }

    /// The application that owns the item.
    ///
    /// - Note: In macOS 26 Tahoe and later, this property always returns
    ///   the Control Center. To get the actual application that created
    ///   the item, use ``sourceApplication``.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// The application that created the item.
    var sourceApplication: NSRunningApplication? {
        guard let sourcePID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: sourcePID)
    }

    /// A name associated with the item that is suited for display.
    var displayName: String {
        /// Converts "UpperCamelCase" to "Title Case".
        func toTitleCase<S: StringProtocol>(_ s: S) -> String {
            String(s).replacing(/([a-z])([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        var fallback: String {
            "Unknown"
        }
        var mappedTitle: String? {
            title.flatMap { $0.starts(with: /Item-\d+/) ? fallback : $0 }
        }
        var bestName: String {
            if isControlItem {
                Constants.displayName
            } else if let sourceApplication {
                sourceApplication.localizedName ??
                sourceApplication.bundleIdentifier ??
                mappedTitle ??
                fallback
            } else if let owningApplication {
                owningApplication.localizedName ??
                owningApplication.bundleIdentifier ??
                mappedTitle ??
                fallback
            } else {
                ownerName ?? mappedTitle ?? fallback
            }
        }

        guard let title else {
            return bestName
        }

        // Most items will use their computed "best name", but we need to
        // handle a few special cases for system items.
        return switch tag.namespace {
        case .passwords, .weather:
            // "PasswordsMenuBarExtra" -> "Passwords"
            // "WeatherMenu" -> "Weather"
            String(toTitleCase(bestName).prefix { !$0.isWhitespace })
        case .controlCenter where title.hasPrefix("BentoBox"):
            bestName
        case .controlCenter where title == "WiFi":
            title
        case .controlCenter where title.hasPrefix("Hearing"):
            // Changed to "Hearing_GlowE" in macOS 15.4.
            String(toTitleCase(title).prefix { $0.isLetter || $0.isNumber })
        case .systemUIServer where title.contains("TimeMachine"):
            // Sonoma:  "TimeMachine.TMMenuExtraHost"
            // Sequoia: "TimeMachineMenuExtra.TMMenuExtraHost"
            "Time Machine"
        case .controlCenter, .systemUIServer:
            // Most system items are hosted by one of these two apps. They
            // usually have descriptive, but unformatted titles, so we'll do
            // some basic formatting ourselves.
            toTitleCase(title.prefix { $0 != "." })
        default:
            bestName
        }
    }

    /// A textual representation of the item.
    var description: String {
        String(describing: tag)
    }

    /// A string to use for logging purposes.
    var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    private init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = itemWindow.ownerPID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.ownerName = itemWindow.ownerName
        self.isOnScreen = itemWindow.isOnScreen
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    private init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = sourcePID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.ownerName = itemWindow.ownerName
        self.isOnScreen = itemWindow.isOnScreen
    }
}

// MARK: - MenuBarItem List

extension MenuBarItem {
    /// Options that specify the menu bar items in a list.
    struct ListOption: OptionSet {
        let rawValue: Int

        /// Specifies menu bar items that are currently on screen.
        static let onScreen = ListOption(rawValue: 1 << 0)

        /// Specifies menu bar items on the currently active space.
        static let activeSpace = ListOption(rawValue: 1 << 1)
    }

    /// Creates and returns a list of menu bar items windows for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     item windows across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar item windows.
    static func getMenuBarItemWindows(on display: CGDirectDisplayID? = nil, option: ListOption) -> [WindowInfo] {
        var bridgingOption: Bridging.MenuBarWindowListOption = .itemsOnly
        var displayBoundsPredicate: (CGWindowID) -> Bool = { _ in true }

        if let display {
            bridgingOption.insert(.onScreen)
            let displayBounds = CGDisplayBounds(display)
            displayBoundsPredicate = { windowID in
                Bridging.windowIntersectsDisplayBounds(windowID, displayBounds)
            }
        } else if option.contains(.onScreen) {
            bridgingOption.insert(.onScreen)
        }
        if option.contains(.activeSpace) {
            bridgingOption.insert(.activeSpace)
        }

        return Bridging.getMenuBarWindowList(option: bridgingOption)
            .reversed().compactMap { windowID in
                guard
                    displayBoundsPredicate(windowID),
                    let window = WindowInfo(windowID: windowID)
                else {
                    return nil
                }
                return window
            }
    }

    /// Creates and returns a list of menu bar items using experimental
    /// source pid retrieval for macOS 26.
    @available(macOS 26.0, *)
    private static func getMenuBarItemsExperimental(on display: CGDirectDisplayID?, option: ListOption) -> [MenuBarItem] {
        getMenuBarItemWindows(on: display, option: option).map { window in
            let sourcePID = SourcePIDContext.getCachedPID(for: window)
            return MenuBarItem(uncheckedItemWindow: window, sourcePID: sourcePID)
        }
    }

    /// Creates and returns a list of menu bar items, defaulting to the
    /// legacy source pid behavior, prior to macOS 26.
    private static func getMenuBarItemsLegacyMethod(on display: CGDirectDisplayID?, option: ListOption) -> [MenuBarItem] {
        getMenuBarItemWindows(on: display, option: option).map { window in
            MenuBarItem(uncheckedItemWindow: window)
        }
    }

    /// Creates and returns a list of menu bar items for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     items across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar items.
    static func getMenuBarItems(on display: CGDirectDisplayID? = nil, option: ListOption) -> [MenuBarItem] {
        if #available(macOS 26.0, *) {
            getMenuBarItemsExperimental(on: display, option: option)
        } else {
            getMenuBarItemsLegacyMethod(on: display, option: option)
        }
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.tag == rhs.tag &&
        lhs.windowID == rhs.windowID &&
        lhs.ownerPID == rhs.ownerPID &&
        lhs.sourcePID == rhs.sourcePID &&
        NSStringFromRect(lhs.bounds) == NSStringFromRect(rhs.bounds) &&
        lhs.title == rhs.title &&
        lhs.ownerName == rhs.ownerName &&
        lhs.isOnScreen == rhs.isOnScreen
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(sourcePID)
        hasher.combine(NSStringFromRect(bounds))
        hasher.combine(title)
        hasher.combine(ownerName)
        hasher.combine(isOnScreen)
    }
}

// MARK: - SourcePIDContext

@available(macOS 26.0, *)
enum SourcePIDContext {
    @MainActor
    static func startCache(with permissions: AppPermissions) {
        Cache.start(with: permissions)
    }

    @discardableResult
    private static func updateCachedPID(for window: WindowInfo) -> pid_t? {
        let windowID = window.windowID

        for runningApp in Cache.getRunningApps() {
            // Since we're running concurrently, we could have a pid
            // at any point.
            if let pid = Cache.getPID(for: windowID) {
                return pid
            }

            // IMPORTANT: These checks help prevent some major thread
            // blocking caused by the AX APIs.
            guard
                runningApp.isFinishedLaunching,
                !runningApp.isTerminated,
                runningApp.activationPolicy != .prohibited
            else {
                continue
            }

            guard
                let app = Application(runningApp),
                let bar: UIElement = try? app.attribute(.extrasMenuBar)
            else {
                continue
            }

            for child in bar.children {
                if let pid = Cache.getPID(for: windowID) {
                    return pid
                }

                // Item window may have moved. Get the current bounds.
                guard let windowBounds = Bridging.getWindowBounds(for: windowID) else {
                    Cache.setPID(nil, for: windowID)
                    return nil
                }

                guard windowBounds == window.bounds else {
                    return nil
                }

                guard
                    let childFrame = child.frame,
                    childFrame.center.distance(to: windowBounds.center) <= 10
                else {
                    continue
                }

                let pid = runningApp.processIdentifier
                Cache.setPID(pid, for: windowID)
                return pid
            }
        }

        return nil
    }

    static func getCachedPID(for window: WindowInfo) -> pid_t? {
        if let pid = Cache.getPID(for: window.windowID) {
            return pid
        }
        return Cache.concurrentQueue.sync {
            updateCachedPID(for: window)
        }
    }
}

// MARK: - SourcePIDContext.Cache
@available(macOS 26.0, *)
extension SourcePIDContext {
    private enum Cache {
        private static var pids = [CGWindowID: pid_t]()
        private static var runningApps = [NSRunningApplication]() {
            willSet {
                let newPIDs = Set(newValue.map { $0.processIdentifier })
                for (key, value) in pids where !newPIDs.contains(value) {
                    pids.removeValue(forKey: key)
                }
            }
            didSet {
                let windows = MenuBarItem.getMenuBarItemWindows(option: .activeSpace)
                for window in windows {
                    concurrentQueue.async {
                        updateCachedPID(for: window)
                    }
                }
            }
        }

        private static let pidsQueue = DispatchQueue.queue(
            label: "MenuBarItem.SourcePIDsContext.pidsQueue",
            qos: .userInteractive
        )
        private static let runningAppsQueue = DispatchQueue.queue(
            label: "MenuBarItem.SourcePIDsContext.runningAppsQueue",
            qos: .userInteractive
        )
        static let concurrentQueue = DispatchQueue.queue(
            label: "MenuBarItem.SourcePIDsContext.concurrentQueue",
            qos: .userInteractive,
            attributes: .concurrent
        )

        private static var cancellable: AnyCancellable?

        @MainActor
        static func start(with permissions: AppPermissions) {
            cancellable.take()?.cancel()

            guard permissions.accessibility.hasPermission else {
                return
            }

            cancellable = NSWorkspace.shared.publisher(for: \.runningApplications)
                .receive(on: runningAppsQueue)
                .sink { runningApps in
                    var runningApps = runningApps
                    if let index = runningApps.firstIndex(where: { $0.bundleIdentifier == "com.apple.controlcenter" }) {
                        runningApps.append(runningApps.remove(at: index))
                    }
                    self.runningApps = runningApps
                }
        }

        static func getPID(for windowID: CGWindowID) -> pid_t? {
            pidsQueue.sync { pids[windowID] }
        }

        static func setPID(_ pid: pid_t?, for windowID: CGWindowID) {
            pidsQueue.sync { pids[windowID] = pid }
        }

        static func getRunningApps() -> [NSRunningApplication] {
            runningAppsQueue.sync { runningApps }
        }
    }
}

// MARK: - MenuBarItemTag Helper

private extension MenuBarItemTag {
    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        let title = itemWindow.title ?? ""
        if title.hasPrefix("Ice.ControlItem") {
            self.namespace = .ice
        } else {
            self.namespace = Namespace(uncheckedItemWindow: itemWindow)
        }
        self.title = title
    }

    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        let title = itemWindow.title ?? ""
        if title.hasPrefix("Ice.ControlItem") {
            self.namespace = .ice
        } else {
            self.namespace = Namespace(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        }
        self.title = title
    }
}

// MARK: - MenuBarItemTag.Namespace Helper

private extension MenuBarItemTag.Namespace {
    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        //
        // Use the name of the owning process as a fallback. The non-localized
        // name seems less likely to change, so let's prefer it as a (somewhat)
        // stable identifier.
        if let app = itemWindow.owningApplication {
            self.init(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
        } else {
            self.init(itemWindow.ownerName)
        }
    }

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        if let sourcePID, let app = NSRunningApplication(processIdentifier: sourcePID) {
            self.init(app.bundleIdentifier ?? app.localizedName)
        } else if let app = itemWindow.owningApplication {
            self.init(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
        } else {
            self.init(itemWindow.ownerName)
        }
    }
}

// MARK: - DispatchQueue Helper

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
