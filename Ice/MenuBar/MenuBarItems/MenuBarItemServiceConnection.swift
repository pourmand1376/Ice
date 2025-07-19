//
//  MenuBarItemServiceConnection.swift
//  Ice
//

import Foundation
import OSLog

// MARK: - MenuBarItemServiceConnection

@available(macOS 26.0, *)
enum MenuBarItemServiceConnection {
    private final class SessionWrapper: Sendable {
        private struct Storage: Sendable {
            let name = MenuBarItemService.name
            let queue: DispatchQueue
            var session: XPCSession?

            private mutating func getOrCreateSession() throws -> XPCSession {
                if let session {
                    return session
                }
                let session = try XPCSession(xpcService: name, options: .inactive)
                session.setPeerRequirement(.isFromSameTeam())
                session.setTargetQueue(queue)
                try session.activate()
                self.session = session
                return session
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
                do {
                    let session = try getOrCreateSession()
                    let reply = try session.sendSync(request)
                    return try reply.decode(as: Response.self)
                } catch {
                    Logger.general.error("Session failed with error \(error)")
                    return nil
                }
            }
        }

        private static let queue = DispatchQueue.targetingGlobalQueue(
            label: "MenuBarItemServiceConnection.queue",
            qos: .userInteractive
        )

        private let storage = OSAllocatedUnfairLock(initialState: Storage(queue: queue))

        deinit {
            cancel(reason: "Session deinitialized")
        }

        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
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

    static func sourcePID(for window: WindowInfo) async -> pid_t? {
        let session = SessionWrapper()
        return await withCheckedContinuation { continuation in
            let response = session.send(
                request: MenuBarItemService.SourcePIDRequest(window: window),
                expecting: MenuBarItemService.SourcePIDResponse.self
            )
            continuation.resume(returning: response?.pid)
        }
    }
}
