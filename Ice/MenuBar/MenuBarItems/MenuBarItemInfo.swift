//
//  MenuBarItemInfo.swift
//  Ice
//

import CoreGraphics

// MARK: - MenuBarItemInfo

/// A simplified version of a menu bar item.
struct MenuBarItemInfo: Hashable, CustomStringConvertible {
    /// The namespace of the info's item.
    let namespace: Namespace

    /// The title of the info's item.
    let title: String

    /// A Boolean value that indicates whether the info's item can be moved.
    var isMovable: Bool {
        !MenuBarItemInfo.immovableItems.contains(self)
    }

    /// A Boolean value that indicates whether the info's item can be hidden.
    var canBeHidden: Bool {
        !MenuBarItemInfo.nonHideableItems.contains(self)
    }

    /// A Boolean value that indicates whether the info's item is one of Ice's
    /// control items.
    var isControlItem: Bool {
        MenuBarItemInfo.controlItems.contains(self)
    }

    /// A string representation of the info.
    var stringValue: String {
        var result = namespace.rawValue
        if !title.isEmpty {
            result.append(":\(title)")
        }
        return result
    }

    /// A textual representation of the info.
    var description: String {
        stringValue
    }

    /// Creates info with the given namespace and title.
    init(namespace: Namespace, title: String) {
        self.namespace = namespace
        self.title = title
    }

    /// Creates info for the control item with the given identifier.
    private init(controlItem identifier: ControlItem.Identifier) {
        self.init(namespace: .ice, title: identifier.rawValue)
    }
}

// MARK: MenuBarItemInfo Constants

extension MenuBarItemInfo {

    // MARK: Special Item Lists

    /// An array of infos for items whose movement is prevented by macOS.
    static let immovableItems: [MenuBarItemInfo] = {
        var items = [clock, controlCenter]
        if #unavailable(macOS 26.0) {
            items.append(siri)
        }
        return items
    }()

    // TODO: MusicRecognition became hideable in what macOS version?
    //
    // At some point, it became possible to hide the "MusicRecognition" item.
    // We need to determine which version of macOS first had this change, and
    // and conditionally exclude the item from this list.
    //
    // We're using macOS 15.3.2 for now, but it could be earlier.
    //
    /// An array of infos for items that can be moved, but cannot be hidden.
    static let nonHideableItems: [MenuBarItemInfo] = {
        var items = [audioVideoModule, faceTime, screenCaptureUI]
        if #unavailable(macOS 15.3.2) {
            items.append(musicRecognition)
        }
        return items
    }()

    /// An array of infos for items representing Ice's control items.
    static let controlItems = ControlItem.Identifier.allCases.map { $0.info }

    // MARK: Control Items

    /// Info for the control item for the visible section.
    static let visibleControlItem = MenuBarItemInfo(controlItem: .visible)

    /// Info for the control item for the hidden section.
    static let hiddenControlItem = MenuBarItemInfo(controlItem: .hidden)

    /// Info for the control item for the always-hidden section.
    static let alwaysHiddenControlItem = MenuBarItemInfo(controlItem: .alwaysHidden)

    // MARK: Other System Items

    /// Info for the "Clock" item.
    static let clock = MenuBarItemInfo(namespace: .controlCenter, title: "Clock")

    /// Info for the "Siri" item.
    static let siri: MenuBarItemInfo = {
        if #available(macOS 26.0, *) {
            MenuBarItemInfo(namespace: .controlCenter, title: "Siri")
        } else {
            MenuBarItemInfo(namespace: .systemUIServer, title: "Siri")
        }
    }()

    /// Info for the "Control Center" item.
    static let controlCenter: MenuBarItemInfo = {
        if #available(macOS 26.0, *) {
            MenuBarItemInfo(namespace: .controlCenter, title: "BentoBox-0")
        } else {
            MenuBarItemInfo(namespace: .controlCenter, title: "BentoBox")
        }
    }()

    /// Info for the item that appears in the menu bar while the screen or system
    /// audio is being recorded.
    static let audioVideoModule = MenuBarItemInfo(namespace: .controlCenter, title: "AudioVideoModule")

    /// Info for the "FaceTime" item.
    static let faceTime = MenuBarItemInfo(namespace: .controlCenter, title: "FaceTime")

    /// Info for the "MusicRecognition" (a.k.a. "Shazam") item.
    static let musicRecognition = MenuBarItemInfo(namespace: .controlCenter, title: "MusicRecognition")

    // TODO: How do we reference this item in macOS 26?
    /// Info for the "stop recording" item that appears in the menu bar during screen
    /// recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = MenuBarItemInfo(namespace: .screenCaptureUI, title: "Item-0")
}

// MARK: MenuBarItemInfo: Codable
extension MenuBarItemInfo: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let components = string.components(separatedBy: ":")
        let count = components.count
        if count > 2 {
            self.namespace = Namespace(components[0])
            self.title = components[1...].joined(separator: ":")
        } else if count == 2 {
            self.namespace = Namespace(components[0])
            self.title = components[1]
        } else if count == 1 {
            self.namespace = Namespace(components[0])
            self.title = ""
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing namespace component"
                )
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

// MARK: - MenuBarItemInfo.Namespace

extension MenuBarItemInfo {
    /// A type that represents a menu bar item namespace.
    struct Namespace: Codable, Hashable, RawRepresentable, CustomStringConvertible {
        /// Private representation of a namespace.
        private enum Kind {
            case null
            case rawValue(String)
        }

        /// The private representation of the namespace.
        private let kind: Kind

        /// The namespace's raw value.
        var rawValue: String {
            switch kind {
            case .null: "<null>"
            case .rawValue(let rawValue): rawValue
            }
        }

        /// A textual representation of the namespace.
        var description: String {
            rawValue
        }

        /// An Optional representation of the namespace that converts
        /// the ``null`` namespace to `nil`.
        var optional: Namespace? {
            switch kind {
            case .null: nil
            case .rawValue: self
            }
        }

        /// Creates a namespace with the given private representation.
        private init(kind: Kind) {
            self.kind = kind
        }

        /// Creates a namespace with the given raw value.
        ///
        /// - Parameter rawValue: The raw value of the namespace.
        init(rawValue: String) {
            self.init(kind: .rawValue(rawValue))
        }

        /// Creates a namespace with the given raw value.
        ///
        /// - Parameter rawValue: The raw value of the namespace.
        init(_ rawValue: String) {
            self.init(rawValue: rawValue)
        }

        /// Creates a namespace with the given optional value.
        ///
        /// If the provided value is `nil`, the namespace is initialized
        /// to the ``null`` namespace.
        ///
        /// - Parameter value: An optional value for the namespace.
        init(_ value: String?) {
            self = value.map { Namespace($0) } ?? .null
        }
    }
}

// MARK: MenuBarItemInfo.Namespace Constants
extension MenuBarItemInfo.Namespace {
    /// The namespace for menu bar items owned by Ice.
    static let ice = Self(Constants.bundleIdentifier)

    /// The namespace for menu bar items owned by "Control Center".
    static let controlCenter = Self("com.apple.controlcenter")

    /// The namespace for menu bar items owned by "System UI Server".
    static let systemUIServer = Self("com.apple.systemuiserver")

    /// The namespace for the "stop recording" menu bar item that appears
    /// during screen recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = Self("com.apple.screencaptureui")

    /// The namespace for the "Passwords" menu bar item.
    static let passwords = Self("com.apple.Passwords.MenuBarExtra")

    /// The namespace for the "Weather" menu bar item.
    static let weather = Self("com.apple.weather.menu")

    /// The null namespace.
    static let null = Self(kind: .null)
}
