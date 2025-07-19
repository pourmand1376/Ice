//
//  Logging.swift
//  Shared
//

import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? ""

    /// Creates a logger using the specified category.
    init(category: String) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}

// MARK: - Shared Loggers

extension Logger {
    /// The general purpose logger.
    static let general = Logger(category: "General")

    /// The logger for hotkey operations.
    static let hotkeys = Logger(category: "Hotkeys")

    /// The logger for serialization operations.
    static let serialization = Logger(category: "Serialization")
}
