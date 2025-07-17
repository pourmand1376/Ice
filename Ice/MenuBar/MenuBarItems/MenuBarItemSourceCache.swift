//
//  MenuBarItemSourceCache.swift
//  Ice
//

import Foundation
import OSLog

// MARK: - MenuBarItemSourceCache

@available(macOS 26.0, *)
enum MenuBarItemSourceHelper {
    private final class SessionWrapper: Sendable {
        enum SessionError: Error, CustomStringConvertible {
            case sessionCreationFailed(any Error)

            var description: String {
                switch self {
                case .sessionCreationFailed(let error):
                    "Session creation failed with error \(error)"
                }
            }
        }

        private struct Storage: Sendable {
            var session: XPCSession?

            var isCancelled: Bool {
                session == nil
            }

            mutating func getOrCreateSession() -> XPCSession? {
                if let session {
                    return session
                }
                do {
                    let session = try XPCSession(xpcService: ServiceIdentifier.menuBarItemService.rawValue, options: .inactive)
                    session.setPeerRequirement(.isFromSameTeam())
                    session.setTargetQueue(xpcQueue)
                    try session.activate()
                    self.session = session
                    return session
                } catch {
                    Logger.general.error("Session creation failed with error \(error)")
                    cancel(reason: "Failure")
                    return nil
                }
            }

            mutating func cancel(reason: String) {
                guard let session = session.take() else {
                    return
                }
                session.cancel(reason: reason)
            }

            mutating func send<Request: Encodable, Response: Decodable>(
                request: Request,
                expecting responseType: Response.Type
            ) -> Response? {
                guard let session = getOrCreateSession() else {
                    return nil
                }
                do {
                    let reply = try session.sendSync(request)
                    return try reply.decode(as: Response.self)
                } catch {
                    Logger.general.error("Sending request failed with error \(error)")
                    return nil
                }
            }
        }

        private let storage = OSAllocatedUnfairLock(initialState: Storage())

        var isCancelled: Bool {
            storage.withLock { $0.isCancelled }
        }

        deinit {
            cancel(reason: "SessionWrapper deinitialized")
        }

        func cancel(reason: String) {
            storage.withLock { storage in
                storage.cancel(reason: reason)
            }
        }

        func send<Request: Encodable, Response: Decodable>(
            request: Request,
            expecting responseType: Response.Type
        ) -> Response? {
            storage.withLock { storage in
                storage.send(request: request, expecting: Response.self)
            }
        }
    }

    private static let xpcQueue = DispatchQueue.queue(
        label: "MenuBarItemSourceCache.xpcQueue",
        qos: .userInteractive
    )

    static func getCachedPID(for window: WindowInfo) async -> pid_t? {
        let session = SessionWrapper()
        return await withCheckedContinuation { continuation in
            let response = session.send(
                request: SourcePIDRequest(window: window),
                expecting: SourcePIDResponse.self
            )
            continuation.resume(returning: response?.sourcePID)
        }
    }
}
