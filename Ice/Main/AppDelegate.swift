//
//  AppDelegate.swift
//  Ice
//

import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared app state.
    let appState = AppState()

    /// Logger for the delegate.
    private let logger = Logger(category: "AppDelegate")

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager(appState: appState).migrateAll()
        Bridging.setConnectionProperty(true, forKey: "SetsCursorInBackground")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the main menu to make more space in the menu bar.
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        #if DEBUG
        // Stop here if running as a preview.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #endif

        // Depending on the permissions state, either perform setup
        // or prompt to grant permissions.
        switch appState.permissions.permissionsState {
        case .hasAll:
            appState.permissions.logger.info("Passed all permissions checks")
            appState.performSetup(hasPermissions: true)
        case .hasRequired:
            appState.permissions.logger.info("Passed required permissions checks")
            appState.performSetup(hasPermissions: true)
        case .missing:
            appState.permissions.logger.info("Failed required permissions checks")
            appState.performSetup(hasPermissions: false)
        }

        Task {
            try await Task.sleep(for: .seconds(3))
            callService()

            try await Task.sleep(for: .seconds(3))
            callService()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        logger.debug("Handling reopen")
        openSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if
            sender.isActive,
            sender.activationPolicy() != .accessory,
            appState.navigationState.isAppFrontmost
        {
            logger.debug("All windows closed - deactivating")
            appState.deactivate(withPolicy: .accessory)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: Other Methods

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        // Small delay makes this more reliable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [appState] in
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }

    func callService() {
        print("Calling XPC service...")

        let session: XPCSession

        do {
            session = try XPCSession(xpcService: "com.jordanbaird.Ice.MenuBarItemService")
        } catch {
            print("Failed to connect to listener, error: \(error)")
            return
        }

        do {
            let request = CalculationRequest(firstNumber: 23, secondNumber: 19)
            let reply = try session.sendSync(request)
            let response = try reply.decode(as: CalculationResponse.self)

            DispatchQueue.main.async {
                print("Received response with result: \(response.result)")
            }
        } catch {
            print("Failed to send message or decode reply: \(error.localizedDescription)")
        }

        session.cancel(reason: "Done with calculation")
    }
}
