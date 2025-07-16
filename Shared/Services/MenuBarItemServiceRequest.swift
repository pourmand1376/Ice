//
//  MenuBarItemServiceRequest.swift
//  Ice
//

protocol MenuBarItemServiceRequest: Codable {
    associatedtype Response: MenuBarItemServiceResponse
}
