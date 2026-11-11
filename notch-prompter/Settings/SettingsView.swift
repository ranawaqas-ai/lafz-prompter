import SwiftUI

// MARK: - Settings Tabs
enum SettingsTab: CaseIterable, Identifiable {
    case script
    case appearance
    case layout
    case behavior
    case voice
    case assist
    case shortcuts
    
    var id: Self { self }
    
        var label: LocalizedStringResource {
            switch self {
            case .script: return "Script"
            case .appearance: return "Appearance"
            case .layout: return "Layout"
            case .behavior: return "Behavior"
            case .voice: return "Voice"
            case .assist: return "Assist"
            case .shortcuts: return "Shortcuts"
            }
        }
    
    var icon: String {
        switch self {
        case .script: return "doc.text"
        case .appearance: return "paintpalette"
        case .layout: return "macwindow"
        case .behavior: return "gearshape"
        case .voice: return "microphone"
        case .assist: return "sparkles"
        case .shortcuts: return "keyboard"
        }
    }
}

struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(Playback.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .script
    @State private var showResetConfirmation = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "\(version)"
    }

    var body: some View {
        // Always rendered: SwiftUI reuses this window after Done hides it, and
        // onAppear does not run again, so content gated on an onAppear
        // animation stayed hidden and the reopened window was blank.
        settingsContent
        .frame(width: 680)
        .frame(minHeight: 560, maxHeight: 760)
        .background(.ultraThinMaterial)
        .alert("Microphone access denied", isPresented: Bindable(playback).showMicrophoneAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable microphone access in System Settings → Privacy & Security → Microphone.")
        }
        .confirmationDialog("Reset Prompter Position?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                playback.reset()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will stop playback and reset the scroll position to the beginning.")
        }
    }
    
    private var settingsContent: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                // TODO: It would be cool to put here Lafz Prompter + version instead of having this in the footer, but I have to also get rid of the window handler with "Lafz Prompter Settings" to make it look good.
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)

                ForEach(SettingsTab.allCases) { tab in
                    HStack(spacing: 7) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 16)
                        Text(tab.label)
                            .font(.system(size: 13, weight: .regular))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTab = tab
                    }
                }

                Spacer()
                
                Text("Lafz Prompter \(appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .opacity(0.6)
            }
            .padding(12)
            .frame(width: 170)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.04))

            Divider()

            // Content
            VStack(spacing: 0) {
                switch selectedTab {
                case .script:
                    ScriptTabView()
                case .appearance:
                    AppearanceTabView()
                case .behavior:
                    BehaviorTabView()
                case .voice:
                    VoiceTabView()
                case .assist:
                    AssistTabView()
                case .layout:
                    LayoutTabView()
                case .shortcuts:
                    KeyboardTabView()
                }

                Divider()
                
                

                HStack {

                    Button {
                        playback.togglePlayback()
                    } label: {
                        HStack(spacing: 4) {
                            if preferences.voiceActivation {
                                Image(systemName: playback.isListening ? "mic.slash.fill" : "mic.fill")
                                    .font(.system(size: 10))
                                Text(playback.isListening ? "Stop listening" : "Listen")
                                    .font(.system(size: 12, weight: .medium))
                            } else {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 10))
                                Text(playback.isPlaying ? "Pause" : "Play")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    }
                    .buttonStyle(.automatic)
                    
                    Button {
                        showResetConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text("Reset")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.automatic)
                    
                    Button {
                        playback.isPrompterVisible.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: playback.isPrompterVisible ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 10))
                            Text(playback.isPrompterVisible ? "Hide" : "Show")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.automatic)
                    .help(playback.isPrompterVisible ? "Hide the prompter window" : "Show the prompter window")

                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
