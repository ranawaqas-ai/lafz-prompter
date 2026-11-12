import SwiftUI

/// The rows of the shortcut list, built from `Shortcut.all` so the list can
/// never miss a shortcut. Opposite pairs share a row.
enum ShortcutList {
    typealias Shortcut = GlobalShortcuts.Shortcut

    struct Row: Equatable {
        let title: String
        let keys: String
        let shortcuts: [Shortcut]
    }

    private static let pairs: [(first: Shortcut, second: Shortcut, title: String, keys: String)] = [
        (.slower, .faster, "Slower, faster", "⌃⌥← →"),
        (.scrollUp, .scrollDown, "Back, ahead", "⌃⌥↑ ↓"),
        (.previousAnswer, .nextAnswer, "Earlier, later answer", "⌃⌥[ ]"),
    ]

    private static let titles: [Shortcut: String] = [
        .playPause: "Play or pause", .showHide: "Hide or show",
        .openScript: "Open a file", .loadClipboard: "From clipboard",
        .assistToggle: "Start or stop", .answerNow: "Answer now", .solveScreen: "Solve the screen",
    ]

    /// The list's own key is shown in its footer, not as a row.
    static func rows(for group: Shortcut.Group) -> [Row] {
        Shortcut.all.filter { $0.group == group && $0 != .showShortcuts }.compactMap { shortcut in
            if pairs.contains(where: { $0.second == shortcut }) { return nil }
            if let pair = pairs.first(where: { $0.first == shortcut }) {
                return Row(title: pair.title, keys: pair.keys, shortcuts: [pair.first, pair.second])
            }
            let keys = shortcut == .answerNow ? "⌃⌥↩" : shortcut.label
            return Row(title: titles[shortcut] ?? shortcut.name, keys: keys, shortcuts: [shortcut])
        }
    }
}

/// Every shortcut, grouped, drawn in the prompter's own theme. ⌃⌥/, Esc or a
/// click closes it.
struct ShortcutOverlay: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ShortcutGuide.self) private var guide
    @Environment(CallAssistSession.self) private var callAssist

    /// The panel grows to at least this while the list is open.
    static let minimumSize = CGSize(width: 500, height: 330)

    var body: some View {
        let color = preferences.prompterTheme.textColor
        ZStack {
            preferences.prompterTheme.backgroundColor.opacity(max(preferences.backgroundOpacity, 0.9))
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 28) {
                    group(.prompter, color: color)
                    group(.scripts, color: color)
                }
                callAssistGroup(color: color)
                Rectangle().fill(color.opacity(0.12)).frame(height: 1)
                Text("⌃⌥/ or Esc to close")
                    .font(.system(size: 12))
                    .foregroundStyle(color.opacity(0.62))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture { guide.closeOverlay() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }

    private func group(_ group: GlobalShortcuts.Shortcut.Group, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header(group.rawValue, color: color)
            ForEach(ShortcutList.rows(for: group), id: \.title) { row($0, color: color) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dimmed while Call Assist is off: its keys do nothing until it starts.
    private func callAssistGroup(color: Color) -> some View {
        let rows = ShortcutList.rows(for: .callAssist)
        let half = (rows.count + 1) / 2
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                header(GlobalShortcuts.Shortcut.Group.callAssist.rawValue, color: color)
                Spacer()
                if !callAssist.isActive {
                    Text("Off · ⌃⌥A starts it").font(.system(size: 12)).foregroundStyle(color.opacity(0.62))
                }
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 9) { ForEach(rows.prefix(half), id: \.title) { row($0, color: color) } }
                VStack(spacing: 9) { ForEach(rows.dropFirst(half), id: \.title) { row($0, color: color) } }
            }
        }
        .opacity(callAssist.isActive ? 1 : 0.55)
    }

    private func header(_ title: String, color: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color.opacity(0.62))
    }

    private func row(_ row: ShortcutList.Row, color: Color) -> some View {
        HStack {
            Text(row.title).foregroundStyle(color)
            Spacer(minLength: 8)
            Keycap(row.keys, color: color)
        }
        .font(.system(size: 14))
    }
}

/// A shortcut drawn as a key: its label in a thin rounded outline.
struct Keycap: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.3), lineWidth: 1))
            .fixedSize()
    }
}

/// "Next time press ⌃⌥P to play or pause", shown for a moment after the
/// same thing was done with the mouse.
struct ShortcutHint: View {
    let shortcut: GlobalShortcuts.Shortcut
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("Next time press")
            Keycap(shortcut.label, color: color)
            Text("to \(shortcut.hintVerb)")
        }
        .font(.system(size: 12))
        .foregroundStyle(color.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(color.opacity(0.1), in: Capsule())
        .frame(height: 36)
        .accessibilityElement(children: .combine)
    }
}
