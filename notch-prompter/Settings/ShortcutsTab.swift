import SwiftUI

// MARK: - Keyboard Tab
struct KeyboardTabView: View {
    @Environment(Preferences.self) private var preferences
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: Bindable(preferences).enableGlobalKeyboardShortcuts)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable global keyboard shortcuts")
                            .font(.system(size: 13, weight: .medium))
                        Text("Control the prompter and Call Assist from any app. Call Assist takes ⌃⌥A only once an API key is saved, and its other keys only during a session.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if preferences.enableGlobalKeyboardShortcuts {
                    Divider()
                    
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 13, weight: .medium))
                    
                    // The same list as ⌃⌥/ shows in the prompter.
                    ForEach(GlobalShortcuts.Shortcut.Group.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(GlobalShortcuts.Shortcut.all.filter { $0.group == group }, id: \.label) {
                                ShortcutRow(title: $0.name, shortcut: $0.label)
                            }
                        }
                    }
                    
                    Divider()
                    
                    Text("Speed Control")
                        .font(.system(size: 13, weight: .medium))
                    
                    SettingSlider(
                        label: "Speed increment",
                        value: Bindable(preferences).speedIncrement,
                        range: 1...10,
                        step: 1,
                        unit: "pt/s"
                    )
                    
                    Text("Amount to increase/decrease speed with keyboard shortcuts")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    
                    Divider()
                    
                    Text("Scroll Control")
                        .font(.system(size: 13, weight: .medium))
                    
                    SettingSlider(
                        label: "Scroll amount",
                        value: Bindable(preferences).manualScrollAmount,
                        range: 10...100,
                        step: 5,
                        unit: "px"
                    )
                    
                    Text("Number of pixels to scroll with keyboard shortcuts")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }
}

// MARK: Shortcut row
struct ShortcutRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            KeycapLabel(shortcut)
        }
        .padding(.vertical, 2)
    }
}

/// A shortcut drawn as a key in Settings: its label in a thin outline.
struct KeycapLabel: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary, lineWidth: 1))
            .fixedSize()
            .accessibilityLabel("Shortcut \(label)")
    }
}
