//
//  MenuBarItemServiceConnection.swift
//  Ice
//

import Foundation
import OSLog

// MARK: - MenuBarItemService.Connection

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC process.
    final class Connection: Sendable {
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's target queue.
        private let queue: DispatchQueue

        /// Creates a new connection.
        private init() {
            let queue = DispatchQueue.targetingGlobalQueue(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive
            )
            self.session = Session(queue: queue)
            self.queue = queue
        }

        /// Starts the connection.
        func start() async {
            await withCheckedContinuation { continuation in
                let response = session.send(
                    request: MenuBarItemService.Request.start,
                    expecting: MenuBarItemService.Response.self
                )
                if case .start = response {
                    continuation.resume()
                } else {
                    Logger.general.warning("Session returned invalid response for Request.start")
                    continuation.resume()
                }
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            await withCheckedContinuation { continuation in
                let response = session.send(
                    request: MenuBarItemService.Request.sourcePID(window),
                    expecting: MenuBarItemService.Response.self
                )
                if case .sourcePID(let pid) = response {
                    continuation.resume(returning: pid)
                } else {
                    Logger.general.warning("Session returned invalid response for Request.sourcePID")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - MenuBarItemService.Session

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A wrapper around an XPC session.
    private final class Session: Sendable {
        /// A session's underlying storage.
        private struct Storage: Sendable {
            private let name = MenuBarItemService.name
            private var session: XPCSession?
            private let queue: DispatchQueue

            init(queue: DispatchQueue) {
                self.queue = queue
            }

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

        /// Protected storage for the underlying XPC session.
        private let storage: OSAllocatedUnfairLock<Storage>

        /// The session's target queue.
        private let queue: DispatchQueue

        /// Creates a new session.
        init(queue: DispatchQueue) {
            self.storage = OSAllocatedUnfairLock(initialState: Storage(queue: queue))
            self.queue = queue
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        /// Sends the given request to the service and returns the response,
        /// decoded as the given type.
        func send<Request: Encodable, Response: Decodable>(
            request: Request,
            expecting responseType: Response.Type
        ) -> Response? {
            storage.withLock { storage in
                storage.send(request: request, expecting: Response.self)
            }
        }
    }
}
