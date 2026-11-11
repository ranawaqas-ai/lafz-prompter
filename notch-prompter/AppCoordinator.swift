import Observation

/// The rules that involve more than one feature, in one place. Each feature
/// model knows only itself; this object watches them and applies the rules.
@MainActor
final class AppCoordinator {
    private let preferences: Preferences
    private let playback: Playback
    private let scripts: ScriptLibrary
    private let callAssist: CallAssistController
    private var tasks: [Task<Void, Never>] = []

    init(preferences: Preferences, playback: Playback, scripts: ScriptLibrary, callAssist: CallAssistController) {
        self.preferences = preferences
        self.playback = playback
        self.scripts = scripts
        self.callAssist = callAssist
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    /// Starts applying the rules. Each rule follows the state it depends on
    /// and acts when that state changes.
    func start() {
        let playback = playback
        let scripts = scripts
        let callAssist = callAssist
        tasks = [
            // 1. Hiding the prompter ends a Call Assist session. (Playback
            //    stops voice listening itself when it is hidden.)
            Task {
                for await visible in Observations({ playback.isPrompterVisible }) where !visible {
                    callAssist.stop()
                }
            },
            // 2. Starting Call Assist shows the prompter, so answers are never
            //    fetched with nothing on screen.
            // 3. While Call Assist runs, the scroll controls move the answer.
            Task {
                for await active in Observations({ callAssist.isActive }) {
                    if active { playback.isPrompterVisible = true }
                    playback.scrollRedirect = active ? { callAssist.nudgeScroll(by: $0) } : nil
                }
            },
            // 6. Picking another script starts it from the top.
            Task {
                for await _ in Observations({ scripts.currentID }).dropFirst() {
                    playback.reset()
                }
            },
        ]
    }
}
