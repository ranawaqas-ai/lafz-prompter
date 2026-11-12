import AppKit

/// Opens the Settings window from outside a SwiftUI view, where
/// `SettingsLink` and `openSettings` are not available.
@MainActor
enum SettingsWindow {
    static func open() {
        NSApp.activate()
        // SwiftUI's identifier for the Settings scene window; unlike the
        // title, it does not change with the app name.
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Not created yet: send the app its own Command-comma, which the
        // Settings scene answers.
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                                     context: nil, characters: ",", charactersIgnoringModifiers: ",",
                                     isARepeat: false, keyCode: 43)
        if let event { NSApp.postEvent(event, atStart: true) }
    }
}
