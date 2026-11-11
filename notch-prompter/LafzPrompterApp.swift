import SwiftUI
import Dependencies
import AppKit
import Combine

@main
struct LafzPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel, callAssist: appDelegate.callAssist,
                         callAssistController: appDelegate.callAssistController,
                         scripts: appDelegate.scripts)
                .onAppear(perform: {
                    NSApp.setActivationPolicy(.regular)
                })
                .onDisappear(perform: {
                    NSApp.setActivationPolicy(.accessory)
                })
        }

        MenuBarExtra {
            MenuContent(viewModel: appDelegate.viewModel, library: appDelegate.scripts)
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
    @Dependency(\.globalShortcuts) private var shortcuts
    let viewModel = PrompterViewModel()
    let callAssist = CallAssistSettings()
    let scripts = ScriptLibrary()
    private(set) lazy var callAssistController = CallAssistController(
        settings: callAssist, dependencies: .live(shortcuts: shortcuts))
    private var prompterWindow: PrompterWindow!
    private var hideObserver: AnyCancellable?
    private var assistStateObserver: AnyCancellable?
    private var shortcutsSettingObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        scripts.attach(to: viewModel)
        prompterWindow = PrompterWindow(viewModel: viewModel, callAssist: callAssistController, scripts: scripts)
        // Hiding the prompter ends a Call Assist session, as it stops voice activation.
        hideObserver = viewModel.$isPrompterVisible
            .filter { !$0 }
            .sink { [weak self] _ in self?.callAssistController.stop() }
        // Starting Call Assist brings the prompter back, so answers are never
        // fetched with nothing on screen, and the scroll shortcuts move the
        // answer instead of the script while it runs.
        assistStateObserver = callAssistController.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                if state == .starting { self.viewModel.isPrompterVisible = true }
                let controller = self.callAssistController
                self.viewModel.scrollRedirect = state == .idle ? nil : { controller.nudgeScroll(by: $0) }
            }
        // One setting turns off every global shortcut, Call Assist's too.
        shortcutsSettingObserver = viewModel.$enableGlobalKeyboardShortcuts
            .sink { [weak self] enabled in self?.callAssistController.shortcutsEnabled = enabled }
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
    @ObservedObject var viewModel: PrompterViewModel
    @ObservedObject var library: ScriptLibrary

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
