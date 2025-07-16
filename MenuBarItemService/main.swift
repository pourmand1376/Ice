//
//  main.swift
//  MenuBarItemService
//

import CoreGraphics
import Foundation
import OSLog

//@main
//enum MenuBarItemService {
//    static func main() throws {
//        _ = try XPCListener(service: ServiceIdentifier.menuBarItemService.rawValue) { request in
//            request.accept { message in
//                performTask(with: message)
//            }
//        }
//        RunLoop.current.run()
//        MenuBarItemSourceCache.start()
//    }
//
//    static func performTask(with message: XPCReceivedMessage) -> (any Encodable)? {
//        do {
//            let request = try message.decode(as: SourcePIDRequest.self)
//            let sourcePID = MenuBarItemSourceCache.getCachedPID(for: request.window)
//            return SourcePIDResponse(sourcePID: sourcePID)
//        } catch {
//            Logger.general.error("Service failed with error \(error)")
//            return nil
//        }
//    }
//}

class MenuBarItemService: NSObject, MenuBarItemServiceProtocol {
    func getCachedPID(for windowID: CGWindowID, with reply: @escaping (Int64) -> Void) {
        let window = WindowInfo(windowID: windowID)
        print(window)
        guard
            let window,
            let sourcePID = MenuBarItemSourceCache.getCachedPID(for: window)
        else {
            reply(.max)
            return
        }
        reply(Int64(sourcePID))
    }
//    func getCachedPID(for window: WindowInfoObject, with reply: @escaping (SourcePIDObject) -> Void) {
//        let sourcePID = MenuBarItemSourceCache.getCachedPID(for: window.window)
//        let response = SourcePIDObject(sourcePID)
//        reply(response)
//    }
}

class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    /// This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        // Configure the connection.
        // First, set the interface that the exported object implements.
        newConnection.exportedInterface = NSXPCInterface(with: (any MenuBarItemServiceProtocol).self)

        // Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
        let exportedObject = MenuBarItemService()
        newConnection.exportedObject = exportedObject

        // Resuming the connection allows the system to deliver more incoming messages.
        newConnection.resume()

        // Returning true from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call invalidate() on the connection and return false.
        return true
    }
}

// Create the delegate for the service.
let delegate = ServiceDelegate()

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener.service()
listener.delegate = delegate

MenuBarItemSourceCache.start()

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()
