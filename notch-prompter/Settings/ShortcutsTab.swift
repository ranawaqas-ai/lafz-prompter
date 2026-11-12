import SwiftUI

// TODO: add option to change shortcuts
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
                    
                    VStack(alignment: .leading, spacing: 12) {
                        ShortcutRow(
                            icon: "play.fill",
                            title: "Play / Pause",
                            shortcut: "⌃ + ⌥ + p"
                        )
                        
                        ShortcutRow(
                            icon: "eye.fill",
                            title: "Show / Hide Prompter",
                            shortcut: "⌃ + ⌥ + h"
                        )
                        
                        ShortcutRow(
                            icon: "arrow.left",
                            title: "Decrease Speed",
                            shortcut: "⌃ + ⌥ + ←"
                        )
                        
                        ShortcutRow(
                            icon: "arrow.right",
                            title: "Increase Speed",
                            shortcut: "⌃ + ⌥ + →"
                        )
                        
                        ShortcutRow(
                            icon: "arrow.up",
                            title: "Scroll Up",
                            shortcut: "⌃ + ⌥ + ↑"
                        )
                        
                        ShortcutRow(
                            icon: "arrow.down",
                            title: "Scroll Down",
                            shortcut: "⌃ + ⌥ + ↓"
                        )

                        ShortcutRow(
                            icon: "folder",
                            title: "Open Script File",
                            shortcut: "⌃ + ⌥ + o"
                        )

                        ShortcutRow(
                            icon: "doc.on.clipboard",
                            title: "Load Script from Clipboard",
                            shortcut: "⌃ + ⌥ + v"
                        )
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
    let icon: String
    let title: LocalizedStringKey
    let shortcut: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 4)
    }
}
