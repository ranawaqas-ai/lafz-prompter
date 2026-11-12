import Dependencies
import Foundation
import Observation

/// Helps people learn the shortcuts: the ⌃⌥/ list of every shortcut, and a
/// short hint after something was done with the mouse that has a shortcut,
/// until that shortcut has been used a few times.
@MainActor @Observable
final class ShortcutGuide {
    typealias Shortcut = GlobalShortcuts.Shortcut

    private(set) var isOverlayShown = false
    /// The shortcut a hint is showing for, if any.
    private(set) var hint: Shortcut?

    /// Set by the coordinator from the "global keyboard shortcuts" setting.
    /// Without global shortcuts there is nothing to hint at.
    var shortcutsEnabled = false {
        didSet {
            guard shortcutsEnabled != oldValue else { return }
            if !shortcutsEnabled { hint = nil }
            applyShortcuts()
        }
    }
    /// Off while Call Assist runs, so nothing distracts from the answer.
    var hintsAllowed = true {
        didSet { if !hintsAllowed { hint = nil } }
    }

    /// After this many presses a shortcut counts as learned: no more hints.
    static let learnedAfter = 3
    @ObservationIgnored var hintDuration: Duration = .seconds(2)

    @ObservationIgnored private let playback: Playback
    @ObservationIgnored @Dependency(\.globalShortcuts) private var shortcuts
    @ObservationIgnored @Dependency(\.settingsStorage) private var storage
    @ObservationIgnored private var presses: [String: Int] = [:]
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    private static let pressesKey = "ShortcutPresses"

    init(playback: Playback) {
        self.playback = playback
        presses = storage.dictionary(forKey: Self.pressesKey) as? [String: Int] ?? [:]
        shortcuts.onPress = { [weak self] shortcut in
            MainActor.assumeIsolated { self?.recordPress(shortcut) }
        }
    }

    // MARK: The shortcut list

    /// Opens or closes the list. It draws in the prompter, so opening it
    /// also shows the prompter.
    func toggleOverlay() {
        isOverlayShown.toggle()
        if isOverlayShown {
            hint = nil
            playback.isPrompterVisible = true
        }
        applyEscape()
    }

    func closeOverlay() {
        guard isOverlayShown else { return }
        isOverlayShown = false
        applyEscape()
    }

    // MARK: Hints

    /// Something with a shortcut was just done with the mouse.
    func usedMouse(for shortcut: Shortcut) {
        guard shortcutsEnabled, hintsAllowed, !isOverlayShown, !isLearned(shortcut) else { return }
        hint = shortcut
        hintTask?.cancel()
        hintTask = Task { [weak self, hintDuration] in
            try? await Task.sleep(for: hintDuration)
            guard !Task.isCancelled, self?.hint == shortcut else { return }
            self?.hint = nil
        }
    }

    func isLearned(_ shortcut: Shortcut) -> Bool {
        presses[shortcut.label, default: 0] >= Self.learnedAfter
    }

    private func recordPress(_ shortcut: Shortcut) {
        presses[shortcut.label, default: 0] += 1
        storage.set(presses, forKey: Self.pressesKey)
        if hint == shortcut { hint = nil }
    }

    // MARK: Registering

    private func applyShortcuts() {
        shortcuts.set([.showShortcuts: { [weak self] in self?.toggleOverlay() }], on: shortcutsEnabled)
        applyEscape()
    }

    /// Esc is held only while the list is open.
    private func applyEscape() {
        shortcuts.set([.closeShortcuts: { [weak self] in self?.closeOverlay() }],
                      on: shortcutsEnabled && isOverlayShown)
    }
}

extension GlobalShortcuts.Shortcut {
    /// What the shortcut does, to finish "Next time press ⌃⌥P to …".
    var hintVerb: String {
        switch self {
        case .playPause: "play or pause"
        case .showHide: "show or hide the prompter"
        case .slower: "slow down"
        case .faster: "speed up"
        case .smallerText: "make the text smaller"
        case .biggerText: "make the text bigger"
        case .scrollUp: "move back"
        case .scrollDown: "move ahead"
        case .openScript: "open a script"
        case .loadClipboard: "load from the clipboard"
        case .assistToggle: "start or stop Call Assist"
        default: name.lowercased()
        }
    }
}
