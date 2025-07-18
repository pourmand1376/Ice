//
//  Listener.swift
//  MenuBarItemService
//

import OSLog
import XPC

/// A wrapper around an xpc listener object.
final class Listener {
    /// An error that can be thrown during listener activation.
    enum ActivationError: Error, CustomStringConvertible {
        case alreadyActive
        case failure(any Error)

        var description: String {
            switch self {
            case .alreadyActive:
                "Listener is already active"
            case .failure(let error):
                "Listener activation failed with error \(error)"
            }
        }
    }

    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying xpc listener object.
    private var listener: XPCListener?

    /// Creates the shared listener.
    private init() { }

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> (any Encodable)? {
        do {
            let request = try message.decode(as: MenuBarItemService.SourcePIDRequest.self)
            let sourcePID = MenuBarItemSourceCache.getCachedPID(for: request.window)
            return MenuBarItemService.SourcePIDResponse(sourcePID: sourcePID)
        } catch {
            Logger.general.error("Service failed with error \(error)")
            return nil
        }
    }

    /// Activates the listener with a same-team requirement, without
    /// checking if it is already active.
    @available(macOS 26.0, *)
    private func uncheckedActivateWithSameTeamRequirement() throws {
        listener = try XPCListener(service: name, requirement: .isFromSameTeam()) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        listener = try XPCListener(service: name) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    ///
    /// - Note: Calling this method on an active listener throws an error.
    func activate() throws(ActivationError) {
        guard listener == nil else {
            throw .alreadyActive
        }
        do {
            if #available(macOS 26.0, *) {
                try uncheckedActivateWithSameTeamRequirement()
            } else {
                try uncheckedActivate()
            }
        } catch {
            throw .failure(error)
        }
    }

    /// Cancels the listener.
    func cancel() {
        listener.take()?.cancel()
    }
}
