import AppKit
import Dependencies

/// Loading a script from the menu or a shortcut: import it, show the
/// prompter when a new script was picked, and explain a failure.
@MainActor
final class ScriptLoader {
    private let library: ScriptLibrary
    private let playback: Playback
    private let showError: @MainActor (String) -> Void
    @Dependency(\.globalShortcuts) private var shortcuts

    /// Set by the coordinator from the "global keyboard shortcuts" setting.
    var shortcutsEnabled = false {
        didSet { if shortcutsEnabled != oldValue { applyShortcutsSetting() } }
    }

    init(library: ScriptLibrary, playback: Playback, showError: @escaping @MainActor (String) -> Void = ScriptLoader.alert) {
        self.library = library
        self.playback = playback
        self.showError = showError
    }

    func openFile() { load { library.showOpenPanel() } }
    func loadClipboard() { load { library.importClipboard() } }
    func select(_ id: UUID) { load { library.select(id) } }

    /// Adds the tutorial back if it was deleted, and plays it from the top.
    func showTutorial() {
        library.restoreTutorial()
        playback.reset()
        playback.isPrompterVisible = true
    }

    private func load(_ action: () -> Void) {
        let before = library.currentID
        action()
        if let error = library.importError {
            library.importError = nil
            showError(error)
        } else if library.currentID != before {
            playback.isPrompterVisible = true
        }
    }

    private func applyShortcutsSetting() {
        shortcuts.set([
            .openScript: { [weak self] in self?.openFile() },
            .loadClipboard: { [weak self] in self?.loadClipboard() },
        ], on: shortcutsEnabled)
    }

    static func alert(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Could not load the script"
        alert.informativeText = message
        alert.runModal()
    }
}
