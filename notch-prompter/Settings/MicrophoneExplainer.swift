import SwiftUI

/// Says why the microphone is needed before macOS asks for it.
struct MicrophoneExplainer: View {
    enum Purpose {
        case voiceActivation, callAssist

        var title: String {
            switch self {
            case .voiceActivation: "Scroll while you speak"
            case .callAssist: "Hear your side of the call"
            }
        }

        var detail: String {
            switch self {
            case .voiceActivation:
                "Lafz uses the microphone only to tell when you're talking. Nothing is recorded or sent."
            case .callAssist:
                "Call Assist transcribes your microphone on this Mac. Audio is never saved; the transcript goes to your AI provider with each question."
            }
        }
    }

    let purpose: Purpose
    let onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tint)
            Text(purpose.title)
                .font(.system(size: 15, weight: .semibold))
            Text(purpose.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("macOS will ask next.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Not Now") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue") {
                    dismiss()
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 320)
    }
}
