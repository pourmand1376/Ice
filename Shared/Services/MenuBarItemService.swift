//
//  MenuBarItemService.swift
//  Shared
//

import Foundation

enum MenuBarItemService {
    static let name = "com.jordanbaird.Ice.MenuBarItemService"
}

extension MenuBarItemService {
    struct SourcePIDRequest: Codable {
        let window: WindowInfo
    }

    struct SourcePIDResponse: Codable {
        let pid: pid_t?
    }
}
