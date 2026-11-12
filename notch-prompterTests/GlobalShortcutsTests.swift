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
    typealias Fakes = CallAssistSessionCharacterisationTests

    private final class App {
        let shortcuts = GlobalShortcuts(registersWithSystem: false)
        let preferences: Preferences
        let playback: Playback
        let settings: CallAssistSettings
        let controller: CallAssistSession
        let coordinator: AppCoordinator
        let files = ScriptLibraryTests.MemoryFiles()
        let scripts: ScriptLibrary
        let loader: ScriptLoader
        private let suite = "lafz-shortcut-tests-\(UUID().uuidString)"

        @MainActor
        init(keys: Set<AssistProvider>) {
            let defaults = UserDefaults(suiteName: suite)!
            let shortcuts = shortcuts
            (preferences, playback) = withDependencies {
                $0.settingsStorage = defaults
                $0.frameClock = .stopped
                $0.globalShortcuts = shortcuts
            } operation: {
                let preferences = Preferences()
                return (preferences, Playback(preferences: preferences))
            }
            (settings, controller) = withDependencies {
                Fakes.useFakes(&$0, defaults: defaults, keys: keys, listener: Fakes.FakeListener(),
                               provider: Fakes.FakeProvider([]),
                               history: AnswerHistoryStore(url: FileManager.default.temporaryDirectory
                                   .appendingPathComponent("shortcuts-\(UUID().uuidString).sqlite")),
                               shortcuts: shortcuts)
            } operation: {
                let settings = CallAssistSettings()
                return (settings, CallAssistSession(settings: settings))
            }
            settings.includeScreen = false
            let files = files
            scripts = withDependencies {
                $0.scriptFiles = files.client
                $0.settingsStorage = defaults
            } operation: { ScriptLibrary() }
            let (playback, scripts) = (playback, scripts)
            loader = withDependencies { $0.globalShortcuts = shortcuts } operation: {
                ScriptLoader(library: scripts, playback: playback, showError: { _ in })
            }
            coordinator = AppCoordinator(preferences: preferences, playback: playback,
                                         scripts: scripts, callAssist: controller,
                                         scriptLoader: loader, panel: AppCoordinatorTests.FakePanel())
            coordinator.start()
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        /// The Settings switch; the coordinator passes it on.
        @MainActor func setShortcutsSetting(_ on: Bool) {
            preferences.enableGlobalKeyboardShortcuts = on
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
        await settle()
        record("global shortcuts switched off during the session")
        app.setShortcutsSetting(true)
        await settle()
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
            "⌃⌥O Open a script file", "⌃⌥V Load a script from the clipboard",
        ].sorted())
    }

    @Test func pressingAPrompterShortcutRunsItsAction() {
        let app = App(keys: [])
        app.shortcuts.press(.playPause)
        #expect(app.playback.isPlaying)
        app.shortcuts.press(.faster)
        #expect(app.preferences.speed == 14)
    }

    @Test func theClipboardShortcutLoadsTheCopiedScriptAndShowsIt() {
        let app = App(keys: [])
        app.playback.isPrompterVisible = false
        app.files.clipboard = ([], "Copied script")
        app.shortcuts.press(.loadClipboard)
        #expect(app.scripts.text == "Copied script")
        #expect(app.playback.isPrompterVisible)
    }

    @Test func showTutorialAgainPlaysTheTutorialFromTheTop() {
        let app = App(keys: [])
        app.scripts.add(text: "My talk", title: nil)
        app.playback.offset = 300
        app.playback.isPrompterVisible = false
        app.loader.showTutorial()
        #expect(app.scripts.current?.id == ScriptLibrary.tutorialID)
        #expect(app.playback.offset == 0)
        #expect(app.playback.isPrompterVisible)
    }
}
