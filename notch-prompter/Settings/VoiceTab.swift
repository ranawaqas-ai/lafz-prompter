import SwiftUI

// MARK: - Voice Tab
struct VoiceTabView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(Playback.self) private var playback
    @State private var explainingMicrophone = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    // Explain the microphone before macOS asks for it.
                    Toggle("", isOn: Binding(
                        get: { preferences.voiceActivation },
                        set: { on in
                            if on, playback.microphoneUndecided {
                                explainingMicrophone = true
                            } else {
                                preferences.voiceActivation = on
                            }
                        }))
                        .labelsHidden()
                        .sheet(isPresented: $explainingMicrophone) {
                            MicrophoneExplainer(purpose: .voiceActivation) { preferences.voiceActivation = true }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice activation")
                            .font(.system(size: 13, weight: .medium))
                        Text("Scroll while you speak. The mic is only on after you press Play (⌃⌥P), and turns off on Pause, Hide, or at the end of the script.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if preferences.voiceActivation {
                    Divider()
                    
                    SettingSlider(
                        label: "Detection threshold",
                        value: Binding(
                            get: { Double(preferences.audioThreshold) },
                            set: { preferences.audioThreshold = Float($0) }
                        ),
                        range: 0.0...0.1,
                        step: 0.005,
                        unit: "%"
                    )
                    
                    Text("Adjust sensitivity for voice detection. Lower values detect quieter speech.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Audio level monitor")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            let rms = playback.audioMonitor?.rmsLevel ?? 0
                            let percentage = min(max(rms / 0.1, 0), 1.0) * 100
                            let color: Color = rms > Float(preferences.audioThreshold) ? .green : .red
                            
                            ProgressView(value: percentage / 100)
                                .progressViewStyle(
                                    LinearProgressViewStyle(tint: color)
                                )
                                .frame(height: 10)
                            
                            Text(percentage / 100, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    
                    Text(playback.isListening ? "Speak to test your microphone levels" : "Press Listen below to see your microphone level")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }
}
