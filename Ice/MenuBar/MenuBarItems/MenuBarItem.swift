//
//  MenuBarItem.swift
//  Ice
//

import AXSwift
import Cocoa

// MARK: - MenuBarItem

/// A representation of an item in the menu bar.
struct MenuBarItem: CustomStringConvertible {
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

    /// The menu bar item info associated with this item.
    let info: MenuBarItemInfo

    /// A Boolean value that indicates whether the item can be moved.
    var isMovable: Bool {
        info.isMovable
    }

    /// A Boolean value that indicates whether the item can be hidden.
    var canBeHidden: Bool {
        info.canBeHidden
    }

    /// A Boolean value that indicates whether the item is one of Ice's
    /// control items.
    var isControlItem: Bool {
        info.isControlItem
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
            if info.isControlItem {
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
        return switch info.namespace {
        case .passwords, .weather:
            // "PasswordsMenuBarExtra" -> "Passwords"
            // "WeatherMenu" -> "Weather"
            String(toTitleCase(bestName).prefix { !$0.isWhitespace })
        case .controlCenter where title.hasPrefix("BentoBox"):
            bestName
        case .controlCenter where title == "WiFi":
            title
        case .controlCenter where title.hasPrefix("Hearing"):
            // Title of this item was changed to "Hearing_GlowE" in macOS 15.4.
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
        String(describing: info)
    }

    /// A string to use for logging purposes.
    var logString: String {
        "<\(info) (windowID: \(windowID))>"
    }

    /// Creates a menu bar item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    private init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = sourcePID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.ownerName = itemWindow.ownerName
        self.isOnScreen = itemWindow.isOnScreen
        self.info = MenuBarItemInfo(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
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

    /// Returns a (potentially cached) identifier for the process that
    /// created a menu bar item window.
    ///
    /// - Note: The source pid is determined using a best effort guess,
    ///   using the Accessibility API to compare the window frame with
    ///   the frames of potential matching elements. Not very reliable,
    ///   or efficient.
    private static func getSourcePID(for window: WindowInfo) -> pid_t? {
        enum Context {
            private static var cache = [CGWindowID: pid_t]()

            static let concurrentQueue = DispatchQueue.queue(
                "MenuBarItem.AXQueue.concurrent",
                qos: .userInteractive,
                concurrent: true
            )
            static let serialQueue = DispatchQueue.queue(
                "MenuBarItem.AXQueue.serial",
                qos: .userInteractive,
                concurrent: false
            )

            static func pid(for windowID: CGWindowID) -> pid_t? {
                serialQueue.sync { cache[windowID] }
            }

            static func set(_ pid: pid_t, for windowID: CGWindowID) {
                serialQueue.sync { cache[windowID] = pid }
            }
        }

        if #available(macOS 26.0, *) {
            let windowID = window.windowID

            if let pid = Context.pid(for: windowID) {
                return pid
            }

            Context.concurrentQueue.async {
                let windowCenter = window.bounds.center

                if
                    let element = try? systemWideElement.elementAtPosition(windowCenter),
                    let parent: UIElement = try? element.attribute(.parent),
                    let role = try? parent.role(),
                    case .menuBar = role,
                    let pid = try? element.pid()
                {
                    Context.set(pid, for: windowID)
                    return
                }

                for runningApp in NSWorkspace.shared.runningApplications {
                    if Context.pid(for: windowID) != nil {
                        return
                    }
                    guard let app = Application(runningApp) else {
                        continue
                    }
                    guard let bar: UIElement = try? app.attribute(.extrasMenuBar) else {
                        continue
                    }
                    for child in bar.children {
                        if Context.pid(for: windowID) != nil {
                            return
                        }
                        if
                            let frame = child.frame,
                            frame.center.distance(to: windowCenter) <= 5
                        {
                            Context.set(runningApp.processIdentifier, for: windowID)
                            return
                        }
                    }
                }
            }

            return nil
        } else {
            return window.ownerPID
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
        let cachedTimeout = UIElement.globalMessagingTimeout
        UIElement.globalMessagingTimeout = 0.1
        defer {
            UIElement.globalMessagingTimeout = cachedTimeout
        }

        return getMenuBarItemWindows(on: display, option: option).map { window in
            let sourcePID = getSourcePID(for: window)
            return MenuBarItem(uncheckedItemWindow: window, sourcePID: sourcePID)
        }
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.windowID == rhs.windowID &&
        lhs.ownerPID == rhs.ownerPID &&
        lhs.sourcePID == rhs.sourcePID &&
        NSStringFromRect(lhs.bounds) == NSStringFromRect(rhs.bounds) &&
        lhs.title == rhs.title &&
        lhs.ownerName == rhs.ownerName &&
        lhs.isOnScreen == rhs.isOnScreen &&
        lhs.info == rhs.info
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(sourcePID)
        hasher.combine(NSStringFromRect(bounds))
        hasher.combine(title)
        hasher.combine(ownerName)
        hasher.combine(isOnScreen)
        hasher.combine(info)
    }
}

// MARK: - MenuBarItemInfo Helper

private extension MenuBarItemInfo {
    /// Creates an item info without checks.
    ///
    /// This initializer does not perform validation on its parameters.
    /// Only call this initializer if you are certain that the window
    /// is a menu bar item, and that the source PID belongs to the
    /// application that created it.
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

// MARK: - MenuBarItemInfo.Namespace Helper

private extension MenuBarItemInfo.Namespace {
    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validation on its parameters.
    /// Only call this initializer if you are certain that the window
    /// is a menu bar item, and that the source PID belongs to the
    /// application that created it.
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
    /// Boilerplate reducer for creating a queue that targets
    /// a global system queue.
    static func queue(_ label: String, qos: DispatchQoS, concurrent: Bool) -> DispatchQueue {
        DispatchQueue(label: label, attributes: concurrent ? .concurrent : [], target: .global(qos: qos.qosClass))
    }
}
