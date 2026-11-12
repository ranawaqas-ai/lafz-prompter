import AppKit

/// Brings the Settings window forward, creating it if needed. Lafz lives in
/// the menu bar and is never the active app, so SwiftUI's `SettingsLink`
/// opens or finds the window but leaves it behind whatever app is in front.
@MainActor
enum SettingsWindow {
    static func open() {
        // The Settings scene switches the app to a regular app while it is
        // open; doing it first lets the activation below take effect.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let window = existing {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        // Not created yet: use the app menu's own Settings item, which the
        // Settings scene answers.
        if let item = settingsMenuItem, let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        }
        // The window appears on the next turn of the run loop; make sure it
        // comes to the front then.
        DispatchQueue.main.async {
            existing?.makeKeyAndOrderFront(nil)
            existing?.orderFrontRegardless()
        }
    }

    /// SwiftUI's identifier for the Settings scene's window; unlike the
    /// title, it does not change with the app's name.
    private static var existing: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
    }

    private static var settingsMenuItem: NSMenuItem? {
        NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "," }
    }
}
