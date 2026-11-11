import SwiftUI
import AppKit
import HotKey
import Combine

@main
struct LafzPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel, callAssist: appDelegate.callAssist,
                         callAssistController: appDelegate.callAssistController)
                .onAppear(perform: {
                    NSApp.setActivationPolicy(.regular)
                })
                .onDisappear(perform: {
                    NSApp.setActivationPolicy(.accessory)
                })
        }

        MenuBarExtra {
            MenuContent(viewModel: appDelegate.viewModel)
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
    private(set) lazy var callAssistController = CallAssistController(settings: callAssist)
    private var prompterWindow: PrompterWindow!
    private var hideObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        prompterWindow = PrompterWindow(viewModel: viewModel, callAssist: callAssistController)
        // Hiding the prompter ends a Call Assist session, as it stops voice activation.
        hideObserver = viewModel.$isPrompterVisible
            .filter { !$0 }
            .sink { [weak self] _ in self?.callAssistController.stop() }
        prompterWindow.show()
        NSApp.setActivationPolicy(.accessory)
    }

    // Covers a quit inside the save debounce window.
    func applicationWillTerminate(_ notification: Notification) {
        viewModel.saveSettings()
    }
}

struct MenuContent: View {
    @ObservedObject var viewModel: PrompterViewModel
    

    
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

        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

//        Button("Help translate") {
//            if let url = URL(string: "https://simplelocalize.io/suggestions/?id=f1f11f9305dc44a2872b6a154dea6edc") {
//                NSWorkspace.shared.open(url)
//            }
//        }
//        #if !APP_STORE_VERSION
        Button("Sponsor the project") {
            if let url = URL(string: "https://jpomykala.gumroad.com/l/notchprompter") {
                NSWorkspace.shared.open(url)
            }
        }
//        #endif
        
        Divider()

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Exit", systemImage: "xmark.circle")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
