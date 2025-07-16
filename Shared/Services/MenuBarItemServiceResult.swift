//
//  MenuBarItemServiceResult.swift
//  Ice
//

enum MenuBarItemServiceResult<Success: MenuBarItemServiceResponse, Failure: Error> {
    case success(Success)
    case failure(Failure)
}
