import AppKit
import HotKey

/// The one place the app's system-wide shortcuts are registered. A global
/// shortcut takes its key combination away from every other app, so each part
/// of the app registers only the shortcuts that do something right now, and
/// the "Global keyboard shortcuts" setting turns them all off.
final class GlobalShortcuts {
    struct Shortcut: Hashable {
        enum Group: String, CaseIterable {
            case prompter = "Prompter"
            case scripts = "Scripts"
            case callAssist = "Call Assist"
        }

        let name: String
        let key: Key
        let label: String
        var group: Group = .prompter
        var modifiers: NSEvent.ModifierFlags.RawValue = NSEvent.ModifierFlags([.control, .option]).rawValue

        // Every shortcut but Esc uses Control-Option.
        static let playPause = Shortcut(name: "Play or pause", key: .p, label: "⌃⌥P")
        static let showHide = Shortcut(name: "Show or hide the prompter", key: .h, label: "⌃⌥H")
        static let faster = Shortcut(name: "Faster", key: .rightArrow, label: "⌃⌥→")
        static let slower = Shortcut(name: "Slower", key: .leftArrow, label: "⌃⌥←")
        static let scrollUp = Shortcut(name: "Scroll up", key: .upArrow, label: "⌃⌥↑")
        static let scrollDown = Shortcut(name: "Scroll down", key: .downArrow, label: "⌃⌥↓")
        static let showShortcuts = Shortcut(name: "Show all shortcuts", key: .slash, label: "⌃⌥/")
        static let openScript = Shortcut(name: "Open a script file", key: .o, label: "⌃⌥O", group: .scripts)
        static let loadClipboard = Shortcut(name: "Load a script from the clipboard", key: .v, label: "⌃⌥V",
                                            group: .scripts)
        static let assistToggle = Shortcut(name: "Start or stop Call Assist", key: .a, label: "⌃⌥A",
                                           group: .callAssist)
        static let answerNow = Shortcut(name: "Answer now", key: .return, label: "⌃⌥Return", group: .callAssist)
        static let solveScreen = Shortcut(name: "Solve the screen", key: .s, label: "⌃⌥S", group: .callAssist)
        static let previousAnswer = Shortcut(name: "Previous answer", key: .leftBracket, label: "⌃⌥[",
                                             group: .callAssist)
        static let nextAnswer = Shortcut(name: "Next answer", key: .rightBracket, label: "⌃⌥]", group: .callAssist)
        /// Closes the shortcut list. Held only while the list is open, so Esc
        /// is never taken from other apps otherwise.
        static let closeShortcuts = Shortcut(name: "Close the shortcut list", key: .escape, label: "Esc",
                                             modifiers: 0)

        /// Every shortcut people use, in the order the shortcut list and
        /// Settings show them. Esc is left out: it only closes the list.
        static let all: [Shortcut] = [
            .playPause, .showHide, .slower, .faster, .scrollUp, .scrollDown, .showShortcuts,
            .openScript, .loadClipboard,
            .assistToggle, .answerNow, .solveScreen, .previousAnswer, .nextAnswer,
        ]
    }

    /// When false the shortcuts are only recorded, never registered with the
    /// system, so tests can check them without taking real keys.
    private let registersWithSystem: Bool
    private var actions: [Shortcut: () -> Void] = [:]
    /// Told about every press, so learning can be counted in one place.
    var onPress: ((Shortcut) -> Void)?
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
        let hotKey = HotKey(key: shortcut.key, modifiers: NSEvent.ModifierFlags(rawValue: shortcut.modifiers))
        hotKey.keyDownHandler = { [weak self] in self?.press(shortcut) }
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

    /// Runs a shortcut's action as its keys do; tests call it directly.
    func press(_ shortcut: Shortcut) {
        guard let action = actions[shortcut] else { return }
        onPress?(shortcut)
        action()
    }
}
