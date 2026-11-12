import Observation

/// The rules that involve more than one feature, in one place. Each feature
/// model knows only itself; this object watches them and applies the rules.
@MainActor
final class AppCoordinator {
    private let preferences: Preferences
    private let playback: Playback
    private let scripts: ScriptLibrary
    private let callAssist: CallAssistSession
    private let scriptLoader: ScriptLoader
    private let guide: ShortcutGuide
    private let panel: PrompterPanel
    private var tasks: [Task<Void, Never>] = []

    init(preferences: Preferences, playback: Playback, scripts: ScriptLibrary,
         callAssist: CallAssistSession, scriptLoader: ScriptLoader, guide: ShortcutGuide,
         panel: PrompterPanel) {
        self.preferences = preferences
        self.playback = playback
        self.scripts = scripts
        self.callAssist = callAssist
        self.scriptLoader = scriptLoader
        self.guide = guide
        self.panel = panel
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    /// Starts applying the rules. Each rule follows the state it depends on
    /// and acts when that state changes.
    func start() {
        let preferences = preferences
        let playback = playback
        let scripts = scripts
        let callAssist = callAssist
        // 5. One setting holds or releases every global shortcut: the
        //    prompter's, script loading's, the shortcut list's and Call Assist's. Applied now, then on each change.
        applyShortcutsSetting()
        // 4. While Call Assist runs, the prompter is hidden from screen
        //    sharing whatever the setting says: the other side of the call
        //    must not see the answer. Applied now, then on each change.
        applyScreenSharing()
        tasks = [
            Task { [weak self] in
                for await _ in Observations({ preferences.hideFromScreenRecording || callAssist.isActive }) {
                    self?.applyScreenSharing()
                }
            },
            Task { [weak self] in
                for await _ in Observations({ preferences.enableGlobalKeyboardShortcuts }) {
                    self?.applyShortcutsSetting()
                }
            },
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
            // 7. While Call Assist runs, no shortcut hints distract from it.
            Task { [guide] in
                for await active in Observations({ callAssist.isActive }) {
                    guide.hintsAllowed = !active
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

    private func applyScreenSharing() {
        panel.isHiddenFromScreenSharing = preferences.hideFromScreenRecording || callAssist.isActive
    }

    private func applyShortcutsSetting() {
        let enabled = preferences.enableGlobalKeyboardShortcuts
        playback.shortcutsEnabled = enabled
        callAssist.shortcutsEnabled = enabled
        scriptLoader.shortcutsEnabled = enabled
        guide.shortcutsEnabled = enabled
    }
}
