import Dependencies
import Foundation
import SnapshotTesting
import Testing
@testable import LafzPrompter

/// Which system-wide shortcuts the app holds in each state. A shortcut held
/// here is a key combination no other app can use, so this list is approved.
@MainActor
@Suite(.serialized)
struct GlobalShortcutsTests {
    typealias Fakes = CallAssistControllerCharacterisationTests

    private final class App {
        let shortcuts = GlobalShortcuts(registersWithSystem: false)
        let viewModel: PrompterViewModel
        let settings: CallAssistSettings
        let controller: CallAssistController
        private let suite = "lafz-shortcut-tests-\(UUID().uuidString)"

        @MainActor
        init(keys: Set<AssistProvider>) {
            let defaults = UserDefaults(suiteName: suite)!
            let shortcuts = shortcuts
            viewModel = withDependencies {
                $0.settingsStorage = defaults
                $0.frameClock = .stopped
                $0.globalShortcuts = shortcuts
            } operation: {
                PrompterViewModel()
            }
            (settings, controller) = withDependencies {
                Fakes.useFakes(&$0, defaults: defaults, keys: keys, listener: Fakes.FakeListener(),
                               provider: Fakes.FakeProvider([]),
                               history: AnswerHistoryStore(url: FileManager.default.temporaryDirectory
                                   .appendingPathComponent("shortcuts-\(UUID().uuidString).sqlite")),
                               shortcuts: shortcuts)
            } operation: {
                let settings = CallAssistSettings()
                return (settings, CallAssistController(settings: settings))
            }
            settings.includeScreen = false
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        /// The Settings switch, as AppDelegate passes it on to Call Assist.
        @MainActor func setShortcutsSetting(_ on: Bool) {
            viewModel.enableGlobalKeyboardShortcuts = on
            controller.shortcutsEnabled = on
        }
    }

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    /// Lets observation loops deliver a change made in Settings.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    @Test func approvedShortcutsInEachState() async {
        let app = App(keys: [.anthropic])
        var report = ""
        func record(_ step: String) {
            report += "== \(step)\n" + app.shortcuts.registered.joined(separator: "\n") + "\n"
        }

        record("launch, Anthropic key saved")
        app.settings.provider = .openAI
        await settle()
        record("OpenAI selected, no key for it")
        app.settings.provider = .anthropic
        await settle()
        record("Anthropic selected again")

        app.shortcuts.press(.assistToggle)
        await until { app.controller.state == .listening }
        record("session running, started with ⌃⌥A")

        app.setShortcutsSetting(false)
        record("global shortcuts switched off during the session")
        app.setShortcutsSetting(true)
        record("switched back on")

        app.shortcuts.press(.assistToggle)
        record("session stopped with ⌃⌥A")

        assertSnapshot(of: report, as: .lines, named: "states")
    }

    @Test func withoutAnyKeyOnlyThePrompterShortcutsAreHeld() {
        let app = App(keys: [])
        #expect(app.shortcuts.registered == [
            "⌃⌥← Slower", "⌃⌥↑ Scroll up", "⌃⌥→ Faster", "⌃⌥↓ Scroll down",
            "⌃⌥H Show or hide the prompter", "⌃⌥P Play or pause",
        ].sorted())
    }

    @Test func pressingAPrompterShortcutRunsItsAction() {
        let app = App(keys: [])
        app.shortcuts.press(.playPause)
        #expect(app.viewModel.isPlaying)
        app.shortcuts.press(.faster)
        #expect(app.viewModel.speed == 14)
    }
}
