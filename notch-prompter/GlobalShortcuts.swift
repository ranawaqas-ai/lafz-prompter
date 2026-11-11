import AppKit
import HotKey

/// The one place the app's system-wide shortcuts are registered. A global
/// shortcut takes its key combination away from every other app, so each part
/// of the app registers only the shortcuts that do something right now, and
/// the "Global keyboard shortcuts" setting turns them all off.
final class GlobalShortcuts {
    struct Shortcut: Hashable {
        let name: String
        let key: Key
        let label: String

        // Every shortcut uses Control-Option.
        static let playPause = Shortcut(name: "Play or pause", key: .p, label: "⌃⌥P")
        static let showHide = Shortcut(name: "Show or hide the prompter", key: .h, label: "⌃⌥H")
        static let faster = Shortcut(name: "Faster", key: .rightArrow, label: "⌃⌥→")
        static let slower = Shortcut(name: "Slower", key: .leftArrow, label: "⌃⌥←")
        static let scrollUp = Shortcut(name: "Scroll up", key: .upArrow, label: "⌃⌥↑")
        static let scrollDown = Shortcut(name: "Scroll down", key: .downArrow, label: "⌃⌥↓")
        static let assistToggle = Shortcut(name: "Start or stop Call Assist", key: .a, label: "⌃⌥A")
        static let answerNow = Shortcut(name: "Answer now", key: .return, label: "⌃⌥Return")
        static let solveScreen = Shortcut(name: "Solve the screen", key: .s, label: "⌃⌥S")
        static let previousAnswer = Shortcut(name: "Previous answer", key: .leftBracket, label: "⌃⌥[")
        static let nextAnswer = Shortcut(name: "Next answer", key: .rightBracket, label: "⌃⌥]")
    }

    /// When false the shortcuts are only recorded, never registered with the
    /// system, so tests can check them without taking real keys.
    private let registersWithSystem: Bool
    private var actions: [Shortcut: () -> Void] = [:]
    private var hotKeys: [Shortcut: HotKey] = [:]

    init(registersWithSystem: Bool = true) {
        self.registersWithSystem = registersWithSystem
    }

    /// Registers or unregisters each shortcut to match `wanted`.
    func set(_ shortcuts: [Shortcut: () -> Void], on wanted: Bool) {
        for (shortcut, action) in shortcuts {
            wanted ? register(shortcut, action) : unregister(shortcut)
        }
    }

    func register(_ shortcut: Shortcut, _ action: @escaping () -> Void) {
        actions[shortcut] = action
        guard registersWithSystem, hotKeys[shortcut] == nil else { return }
        let hotKey = HotKey(key: shortcut.key, modifiers: [.control, .option])
        hotKey.keyDownHandler = { [weak self] in self?.actions[shortcut]?() }
        hotKeys[shortcut] = hotKey
    }

    func unregister(_ shortcut: Shortcut) {
        actions[shortcut] = nil
        hotKeys[shortcut] = nil
    }

    /// The registered shortcuts, in a stable order, as "⌃⌥P Play or pause".
    var registered: [String] {
        actions.keys.map { "\($0.label) \($0.name)" }.sorted()
    }

    /// Runs a shortcut's action as if its keys were pressed; for tests.
    func press(_ shortcut: Shortcut) {
        actions[shortcut]?()
    }
}
