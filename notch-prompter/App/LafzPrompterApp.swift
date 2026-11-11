import SwiftUI
import AppKit

@main
struct LafzPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.preferences)
                .environment(appDelegate.playback)
                .environment(appDelegate.scripts)
                .environment(appDelegate.callAssist)
                .environment(appDelegate.callAssistSession)
                .onAppear(perform: {
                    NSApp.setActivationPolicy(.regular)
                })
                .onDisappear(perform: {
                    NSApp.setActivationPolicy(.accessory)
                })
        }

        MenuBarExtra {
            MenuContent()
                .environment(appDelegate.playback)
                .environment(appDelegate.preferences)
                .environment(appDelegate.scripts)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 18
                $0.size.width = 18 / ratio
                $0.isTemplate = true
                return $0
            }(NSImage(named: "MenuBarIcon")!)

            Image(nsImage: image)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Creates the feature models, the prompter window and the coordinator that
/// applies the rules between them. Services come from the dependency
/// container (notch-prompter/Services).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    private(set) lazy var playback = Playback(preferences: preferences)
    let callAssist = CallAssistSettings()
    let scripts = ScriptLibrary()
    private(set) lazy var callAssistSession = CallAssistSession(settings: callAssist)
    private var prompterWindow: PrompterWindowController!
    private var coordinator: AppCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        scripts.ensureCurrentScript()
        prompterWindow = PrompterWindowController(preferences: preferences, playback: playback,
                                                  callAssist: callAssistSession, scripts: scripts)
        coordinator = AppCoordinator(preferences: preferences, playback: playback,
                                     scripts: scripts, callAssist: callAssistSession,
                                     panel: prompterWindow)
        coordinator.start()
        prompterWindow.show()
        NSApp.setActivationPolicy(.accessory)
    }

    // Keeps the stored settings complete, and covers a quit inside the
    // script library's save debounce.
    func applicationWillTerminate(_ notification: Notification) {
        preferences.saveAll()
        scripts.flush()
    }
}

struct MenuContent: View {
    @Environment(Playback.self) private var playback
    @Environment(Preferences.self) private var preferences
    @Environment(ScriptLibrary.self) private var library

    var body: some View {
        Button {
            playback.isPrompterVisible.toggle()
        } label: {
            Label(playback.isPrompterVisible ? "Hide Prompter" : "Show Prompter",
                  systemImage: playback.isPrompterVisible ? "eye.slash" : "eye")
        }
        .keyboardShortcut("h", modifiers: [.control, .option])
        
        Divider()
        
        Button {
            playback.togglePlayback()
        }
        label: {
            if preferences.voiceActivation {
                Label(playback.isListening ? "Stop Listening" : "Start Listening",
                      systemImage: playback.isListening ? "mic.slash" : "mic")
            } else {
                Label(playback.isPlaying ? "Pause" : "Play",
                      systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
            }
        }
        .keyboardShortcut("p", modifiers: [.control, .option])

        Button {
            playback.reset()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }

        Divider()

        Button {
            load { library.importClipboard() }
        } label: {
            Label("Load Script from Clipboard", systemImage: "doc.on.clipboard")
        }

        Button {
            load { library.showOpenPanel() }
        } label: {
            Label("Open Script…", systemImage: "folder")
        }

        Menu {
            ForEach(library.scripts.prefix(12)) { script in
                Toggle(script.title, isOn: Binding(
                    get: { library.currentID == script.id },
                    set: { if $0 { load { library.select(script.id) } } }))
            }
        } label: {
            Label("Scripts", systemImage: "doc.text")
        }

        Divider()

        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Exit", systemImage: "xmark.circle")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    /// Loads a script from the menu bar and brings the prompter up with it.
    /// A failed import has no Settings window to show in, so it is an alert.
    private func load(_ action: () -> Void) {
        let before = library.currentID
        action()
        if let error = library.importError {
            library.importError = nil
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Could not load the script"
            alert.informativeText = error
            alert.runModal()
        } else if library.currentID != before {
            playback.isPrompterVisible = true
        }
    }
}
