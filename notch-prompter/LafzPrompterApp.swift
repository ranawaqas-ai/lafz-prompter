import SwiftUI
import AppKit

@main
struct LafzPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .environment(appDelegate.scripts)
                .environment(appDelegate.callAssist)
                .environment(appDelegate.callAssistController)
                .onAppear(perform: {
                    NSApp.setActivationPolicy(.regular)
                })
                .onDisappear(perform: {
                    NSApp.setActivationPolicy(.accessory)
                })
        }

        MenuBarExtra {
            MenuContent(viewModel: appDelegate.viewModel)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = PrompterViewModel()
    let callAssist = CallAssistSettings()
    let scripts = ScriptLibrary()
    private(set) lazy var callAssistController = CallAssistController(settings: callAssist)
    private var prompterWindow: PrompterWindow!
    private var hideTask: Task<Void, Never>?
    private var assistStateTask: Task<Void, Never>?
    private var shortcutsSettingTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        scripts.attach(to: viewModel)
        prompterWindow = PrompterWindow(viewModel: viewModel, callAssist: callAssistController, scripts: scripts)
        // Hiding the prompter ends a Call Assist session, as it stops voice activation.
        let viewModel = viewModel
        hideTask = Task { [callAssistController] in
            for await visible in Observations({ viewModel.isPrompterVisible }) where !visible {
                callAssistController.stop()
            }
        }
        // Starting Call Assist brings the prompter back, so answers are never
        // fetched with nothing on screen, and the scroll shortcuts move the
        // answer instead of the script while it runs.
        let controller = callAssistController
        assistStateTask = Task { [weak self] in
            for await active in Observations({ controller.isActive }) {
                guard let self else { return }
                if active { self.viewModel.isPrompterVisible = true }
                self.viewModel.scrollRedirect = active ? { controller.nudgeScroll(by: $0) } : nil
            }
        }
        // One setting turns off every global shortcut, Call Assist's too.
        shortcutsSettingTask = Task { [callAssistController] in
            for await enabled in Observations({ viewModel.enableGlobalKeyboardShortcuts }) {
                callAssistController.shortcutsEnabled = enabled
            }
        }
        prompterWindow.show()
        NSApp.setActivationPolicy(.accessory)
    }

    // Covers a quit inside the save debounce window.
    func applicationWillTerminate(_ notification: Notification) {
        viewModel.saveSettings()
        scripts.updateCurrent(text: viewModel.text)
        scripts.flush()
    }
}

struct MenuContent: View {
    @Bindable var viewModel: PrompterViewModel
    @Environment(ScriptLibrary.self) private var library

    var body: some View {
        Button {
            viewModel.isPrompterVisible.toggle()
        } label: {
            Label(viewModel.isPrompterVisible ? "Hide Prompter" : "Show Prompter",
                  systemImage: viewModel.isPrompterVisible ? "eye.slash" : "eye")
        }
        .keyboardShortcut("h", modifiers: [.control, .option])
        
        Divider()
        
        Button {
            viewModel.togglePlayback()
        }
        label: {
            if viewModel.voiceActivation {
                Label(viewModel.isListening ? "Stop Listening" : "Start Listening",
                      systemImage: viewModel.isListening ? "mic.slash" : "mic")
            } else {
                Label(viewModel.isPlaying ? "Pause" : "Play",
                      systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
        }
        .keyboardShortcut("p", modifiers: [.control, .option])

        Button {
            viewModel.reset()
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
            viewModel.isPrompterVisible = true
        }
    }
}
