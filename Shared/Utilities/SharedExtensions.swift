//
//  SharedExtensions.swift
//  Ice
//

import CoreGraphics

// MARK: - CGError

extension CGError {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .success: "\(rawValue): success"
        case .failure: "\(rawValue): failure"
        case .illegalArgument: "\(rawValue): illegalArgument"
        case .invalidConnection: "\(rawValue): invalidConnection"
        case .invalidContext: "\(rawValue): invalidContext"
        case .cannotComplete: "\(rawValue): cannotComplete"
        case .notImplemented: "\(rawValue): notImplemented"
        case .rangeCheck: "\(rawValue): rangeCheck"
        case .typeCheck: "\(rawValue): typeCheck"
        case .invalidOperation: "\(rawValue): invalidOperation"
        case .noneAvailable: "\(rawValue): noneAvailable"
        @unknown default: "\(rawValue): unknown"
        }
    }
}

// MARK: - DispatchQueue

extension DispatchQueue {
    /// Creates and returns a new dispatch queue that targets the global
    /// system queue with the specified quality-of-service class.
    static func globalTargetingQueue(
        label: String,
        qos: DispatchQoS.QoSClass,
        attributes: Attributes = []
    ) -> DispatchQueue {
        let target: DispatchQueue = .global(qos: qos)
        return DispatchQueue(label: label, attributes: attributes, target: target)
    }
}
