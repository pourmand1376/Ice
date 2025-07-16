//
//  Service.swift
//  MenuBarItemService
//

import Foundation
import XPC

@main
enum Service {
    static func main() throws {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw ServiceError.missingBundleIdentifier
        }

        do {
            let listener = try XPCListener(service: bundleIdentifier, options: .inactive) { request in
                request.accept { message in
                    performTask(with: message)
                }
            }
            try listener.activate()
        } catch {
            throw ServiceError.listenerCreationFailed(error)
        }

        dispatchMain()
    }

    static func performTask(with message: XPCReceivedMessage) -> Encodable? {
        do {
            // Decode the message from the received message.
            let request = try message.decode(as: CalculationRequest.self)

            // Return an encodable response that will get sent back to the client.
            return CalculationResponse(result: request.firstNumber + request.secondNumber)
        } catch {
            print("Failed to decode received message, error: \(error)")
            return nil
        }
    }
}

enum ServiceError: Error, CustomStringConvertible {
    case missingBundleIdentifier
    case listenerCreationFailed(any Error)

    var description: String {
        switch self {
        case .missingBundleIdentifier:
            "Missing bundle identifier"
        case .listenerCreationFailed(let error):
            "Listener creation failed with error \(error)"
        }
    }
}
