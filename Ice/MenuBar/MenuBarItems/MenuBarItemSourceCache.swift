//
//  MenuBarItemSourceCache.swift
//  Ice
//

import Foundation
import OSLog

// MARK: - MenuBarItemSourceCache

@available(macOS 26.0, *)
enum MenuBarItemSourceHelper {
    private static let serialWorkQueue = DispatchQueue(
        label: "MenuBarItemSourceCache.serialWorkQueue",
        qos: .userInteractive
    )

    /*
     To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

         connectionToService = NSXPCConnection(serviceName: "com.jordanbaird.Helper")
         connectionToService.remoteObjectInterface = NSXPCInterface(with: (any HelperProtocol).self)
         connectionToService.resume()

     Once you have a connection to the service, you can use it like this:

         if let proxy = connectionToService.remoteObjectProxy as? HelperProtocol {
             proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
                 NSLog("Result of calculation is: \(result)")
             }
         }

     And, when you are finished with the service, clean up the connection like this:

         connectionToService.invalidate()
    */

    static let semaphore = DispatchSemaphore(value: 1)
    static func getCachedPID(for window: WindowInfo) -> pid_t? {
        var sourcePID: pid_t?

        let connection = NSXPCConnection(serviceName: ServiceIdentifier.menuBarItemService.rawValue)
        connection.remoteObjectInterface = NSXPCInterface(with: (any MenuBarItemServiceProtocol).self)
        connection.resume()

        if let proxy = connection.remoteObjectProxy as? MenuBarItemServiceProtocol {
            print("HAS PROXY")
            serialWorkQueue.async {
                proxy.getCachedPID(for: window.windowID) { reply in
                    print(reply)
                    if let pid = Int32(exactly: reply) {
                        sourcePID = pid
                    }
                    semaphore.signal()
                }
            }
        } else {
            print("NO PROXY")
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)
        connection.invalidate()

        print("AA", sourcePID)

        return sourcePID
    }
}
