//
//  MenuBarItemService1.swift
//  Ice
//

import CoreGraphics
import Foundation

@objc protocol MenuBarItemServiceProtocol {
    func getCachedPID(for windowID: CGWindowID, with reply: @escaping (Int64) -> Void)
}

class WindowInfoObject: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true

    let window: WindowInfo

    init(_ window: WindowInfo) {
        self.window = window
    }

    required init?(coder: NSCoder) {
        guard
            let data = coder.decodeData(),
            let window = try? JSONDecoder().decode(WindowInfo.self, from: data)
        else {
            return nil
        }
        self.window = window
    }

    func encode(with coder: NSCoder) {
        if let data = try? JSONEncoder().encode(window) {
            coder.encode(data)
        }
    }
}

class SourcePIDObject: NSObject {
    let sourcePID: pid_t?

    init(_ pid: pid_t?) {
        self.sourcePID = pid
    }
}

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
