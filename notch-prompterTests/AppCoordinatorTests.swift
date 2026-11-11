import Dependencies
import Foundation
import SnapshotTesting
import Testing
@testable import LafzPrompter

/// The rules that span features, each recorded as an approved transcript of
/// what the user would see after each step.
@MainActor
@Suite(.serialized)
struct AppCoordinatorTests {
    typealias Fakes = CallAssistSessionCharacterisationTests

    /// The prompter window, recording what the rules set on it.
    final class FakePanel: PrompterPanel {
        var isHiddenFromScreenSharing = false
    }

    /// The app's models wired to fakes, with the coordinator running.
    final class App {
        let shortcuts = GlobalShortcuts(registersWithSystem: false)
        let preferences: Preferences
        let playback: Playback
        let scripts: ScriptLibrary
        let callAssist: CallAssistSession
        let coordinator: AppCoordinator
        let panel = FakePanel()
        private let suite = "lafz-coordinator-tests-\(UUID().uuidString)"
        private var log: [String] = []

        @MainActor
        init() {
            let defaults = UserDefaults(suiteName: suite)!
            let files = ScriptLibraryTests.MemoryFiles()
            let shortcuts = shortcuts
            (preferences, playback, scripts, callAssist) = withDependencies {
                Fakes.useFakes(&$0, defaults: defaults, keys: Set(AssistProvider.allCases),
                               listener: Fakes.FakeListener(), provider: Fakes.FakeProvider([]),
                               history: AnswerHistoryStore(url: FileManager.default.temporaryDirectory
                                   .appendingPathComponent("coordinator-\(UUID().uuidString).sqlite")),
                               shortcuts: shortcuts)
                $0.frameClock = .stopped
                $0.scriptFiles = files.client
            } operation: {
                let preferences = Preferences()
                let settings = CallAssistSettings()
                settings.includeScreen = false
                return (preferences, Playback(preferences: preferences), ScriptLibrary(),
                        CallAssistSession(settings: settings))
            }
            coordinator = AppCoordinator(preferences: preferences, playback: playback,
                                         scripts: scripts, callAssist: callAssist, panel: panel)
            coordinator.start()
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        /// Records the state the rules touch after a step.
        @MainActor func record(_ step: String) {
            log.append("""
                == \(step)
                prompter shown: \(playback.isPrompterVisible), playing: \(playback.isPlaying), offset: \(Int(playback.offset))
                hidden from screen sharing: \(panel.isHiddenFromScreenSharing)
                call assist: \(callAssist.state), scroll nudges: \(callAssist.scrollNudge.sequence) (last \(Int(callAssist.scrollNudge.delta)))
                """)
        }

        var transcript: String { log.joined(separator: "\n") }
    }

    /// Lets the coordinator's observation loops deliver a change.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    private func startAssist(_ app: App) async {
        app.callAssist.start()
        for _ in 0..<300 where app.callAssist.state != .listening {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await settle()
    }

    @Test func rule1HidingThePrompterEndsCallAssist() async {
        let app = App()
        await settle()
        await startAssist(app)
        app.record("Call Assist running")
        app.playback.isPrompterVisible = false
        await settle()
        app.record("prompter hidden")
        assertSnapshot(of: app.transcript, as: .lines, named: "rule1")
    }

    @Test func rule2StartingCallAssistShowsThePrompter() async {
        let app = App()
        await settle()
        app.playback.isPrompterVisible = false
        await settle()
        app.record("prompter hidden, Call Assist off")
        await startAssist(app)
        app.record("Call Assist started")
        assertSnapshot(of: app.transcript, as: .lines, named: "rule2")
    }

    @Test func rule3WhileCallAssistRunsScrollingMovesTheAnswer() async {
        let app = App()
        await settle()
        app.playback.scrollDown()
        app.record("scrolled down with Call Assist off")
        await startAssist(app)
        app.playback.scrollDown()
        app.playback.scrollUp()
        app.record("scrolled down and up with Call Assist running")
        app.callAssist.stop()
        await settle()
        app.playback.scrollDown()
        app.record("scrolled down after Call Assist stopped")
        assertSnapshot(of: app.transcript, as: .lines, named: "rule3")
    }

    @Test func rule4CallAssistAlwaysHidesThePrompterFromScreenSharing() async {
        let app = App()
        await settle()
        app.record("launch, setting off")
        await startAssist(app)
        app.record("Call Assist running, setting off")
        app.callAssist.stop()
        await settle()
        app.record("Call Assist stopped")
        app.preferences.hideFromScreenRecording = true
        await settle()
        app.record("setting switched on")
        await startAssist(app)
        app.callAssist.stop()
        await settle()
        app.record("Call Assist ran and stopped, setting on")
        assertSnapshot(of: app.transcript, as: .lines, named: "rule4")
    }

    @Test func rule6PickingAnotherScriptStartsItFromTheTop() async {
        let app = App()
        app.scripts.add(text: "First script", title: nil)
        await settle()
        app.playback.play()
        app.playback.offset = 120
        app.record("first script playing")
        app.scripts.add(text: "Second script", title: nil)
        await settle()
        app.record("second script added, which picks it")
        app.playback.play()
        app.playback.offset = 40
        app.scripts.text = "Second script, edited"
        await settle()
        app.record("current script edited while playing")
        assertSnapshot(of: app.transcript, as: .lines, named: "rule6")
    }
}
