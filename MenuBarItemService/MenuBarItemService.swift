//
//  MenuBarItemService.swift
//  MenuBarItemService
//

import OSLog
import XPC

@main
enum MenuBarItemService {
    static func main() throws {
        _ = try XPCListener(service: ServiceIdentifier.menuBarItemService.rawValue) { request in
            request.accept { message in
                performTask(with: message)
            }
        }
        MenuBarItemSourceCache.start()
        RunLoop.current.run()
    }

    static func performTask(with message: XPCReceivedMessage) -> (any Encodable)? {
        do {
            let request = try message.decode(as: SourcePIDRequest.self)
            let sourcePID = MenuBarItemSourceCache.getCachedPID(for: request.window)
            return SourcePIDResponse(sourcePID: sourcePID)
        } catch {
            Logger.general.error("Service failed with error \(error)")
            return nil
        }
    }
}
