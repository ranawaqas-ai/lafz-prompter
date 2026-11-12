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
                .environment(appDelegate.updater)
                .onAppear(perform: {
                    NSApp.setActivationPolicy(.regular)
                })
                .onDisappear(perform: {
                    NSApp.setActivationPolicy(.accessory)
                })
        }

        MenuBarExtra {
            MenuContent(loader: appDelegate.scriptLoader, guide: appDelegate.shortcutGuide)
                .environment(appDelegate.playback)
                .environment(appDelegate.preferences)
                .environment(appDelegate.scripts)
                .environment(appDelegate.updater)
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
    let updater = Updater()
    private(set) lazy var callAssistSession = CallAssistSession(settings: callAssist)
    private(set) lazy var scriptLoader = ScriptLoader(library: scripts, playback: playback)
    private(set) lazy var shortcutGuide = ShortcutGuide(playback: playback)
    private var prompterWindow: PrompterWindowController!
    private var coordinator: AppCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        scripts.ensureCurrentScript()
        prompterWindow = PrompterWindowController(preferences: preferences, playback: playback,
                                                  callAssist: callAssistSession, scripts: scripts,
                                                  guide: shortcutGuide)
        coordinator = AppCoordinator(preferences: preferences, playback: playback,
                                     scripts: scripts, callAssist: callAssistSession,
                                     scriptLoader: scriptLoader, guide: shortcutGuide, panel: prompterWindow)
        coordinator.start()
        prompterWindow.show()
        NSApp.setActivationPolicy(.accessory)
    }

    // Keeps the stored settings complete, and covers a quit inside the
    // script library's save debounce.
    /// Opening the app again (from Finder, Spotlight or the Dock) opens
    /// Settings: the one way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.open()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        preferences.saveAll()
        scripts.flush()
    }
}

struct MenuContent: View {
    @Environment(Playback.self) private var playback
    @Environment(Preferences.self) private var preferences
    @Environment(ScriptLibrary.self) private var library
    @Environment(Updater.self) private var updater
    let loader: ScriptLoader
    let guide: ShortcutGuide

    var body: some View {
        Button {
            playback.isPrompterVisible.toggle()
            guide.usedMouse(for: .showHide)
        } label: {
            Label(playback.isPrompterVisible ? "Hide Prompter" : "Show Prompter",
                  systemImage: playback.isPrompterVisible ? "eye.slash" : "eye")
        }
        .keyboardShortcut("h", modifiers: [.control, .option])
        
        Divider()
        
        Button {
            playback.togglePlayback()
            guide.usedMouse(for: .playPause)
        } label: {
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
            loader.loadClipboard()
            guide.usedMouse(for: .loadClipboard)
        } label: {
            Label("Load Script from Clipboard", systemImage: "doc.on.clipboard")
        }
        .keyboardShortcut("v", modifiers: [.control, .option])

        Button {
            loader.openFile()
            guide.usedMouse(for: .openScript)
        } label: {
            Label("Open Script…", systemImage: "folder")
        }
        .keyboardShortcut("o", modifiers: [.control, .option])

        Menu {
            ForEach(library.scripts.prefix(12)) { script in
                Toggle(script.title, isOn: Binding(
                    get: { library.currentID == script.id },
                    set: { if $0 { loader.select(script.id) } }))
            }
        } label: {
            Label("Scripts", systemImage: "doc.text")
        }

        Divider()

        Button {
            loader.showTutorial()
        } label: {
            Label("Show Tutorial Again", systemImage: "graduationcap")
        }

        Button {
            guide.toggleOverlay()
        } label: {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
        }
        .keyboardShortcut("/", modifiers: [.control, .option])

        // A plain button: SettingsLink leaves the window behind the app in front.
        Button {
            SettingsWindow.open()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: [.command])

        if updater.isAvailable {
            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
            }
            .disabled(!updater.canCheckForUpdates)
        }

        Divider()

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Quit Lafz Prompter", systemImage: "xmark.circle")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
