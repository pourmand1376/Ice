//
//  MenuBarItemServiceTypes.swift
//  Ice
//

import CoreGraphics
import Foundation

// A sample codable type that contains two numbers to be added together.
struct CalculationRequest: Codable {
    let firstNumber: Int
    let secondNumber: Int
}

// A sample codable type that contains the result of a calculation.
struct CalculationResponse: Codable {
    let result: Int
}

struct SourcePIDRequest: Codable {
    let window: WindowInfo
}

struct SourcePIDResponse: Codable {
    let sourcePID: pid_t?
}
