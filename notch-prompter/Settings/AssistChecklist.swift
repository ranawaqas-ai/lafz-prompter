import AppKit
import AVFoundation
import SwiftUI

/// What Call Assist still needs, at the top of the Assist tab until the
/// required items are done.
struct AssistChecklist: View {
    let controller: CallAssistSession
    let providerName: String
    /// Permissions change outside the app, so the checklist is read again
    /// whenever the app comes forward or a button here is used.
    @State private var readiness: AssistReadiness?
    @State private var explainingMicrophone = false

    var body: some View {
        let state = readiness ?? controller.readiness
        Group {
            if !state.isComplete {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Set up Call Assist").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(state.requiredDone) of \(AssistReadiness.requiredCount)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    row(done: state.hasKey, title: "AI provider key",
                        detail: state.hasKey ? "\(providerName) key saved" : "Add one under AI provider below")
                    microphoneRow(state.microphone)
                    row(done: state.heardSystemAudio, title: "System audio",
                        detail: state.heardSystemAudio ? "Heard the other side"
                            : "The other side of the call. macOS asks the first time Call Assist starts.")
                    row(done: state.screenRecording, optional: true, title: "Screen recording (optional)",
                        detail: "Only for answers with a screenshot, and ⌃⌥S") {
                        Button("Allow…") {
                            controller.requestScreenRecording()
                            refresh()
                        }
                    }
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .sheet(isPresented: $explainingMicrophone) {
            MicrophoneExplainer(purpose: .callAssist) {
                Task {
                    _ = await controller.requestMicrophone()
                    refresh()
                }
            }
        }
    }

    private func microphoneRow(_ status: AVAuthorizationStatus) -> some View {
        row(done: status == .authorized, title: "Microphone", detail: "Your side of the call") {
            switch status {
            case .notDetermined:
                Button("Allow…") { explainingMicrophone = true }
            case .denied, .restricted:
                Button("Open System Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            default:
                EmptyView()
            }
        }
    }

    private func row(done: Bool, optional: Bool = false, title: String, detail: String) -> some View {
        row(done: done, optional: optional, title: title, detail: detail) { EmptyView() }
    }

    private func row<Action: View>(done: Bool, optional: Bool = false, title: String, detail: String,
                                   @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : (optional ? "circle.dashed" : "circle"))
                .foregroundStyle(done ? Color.green : Color.secondary)
                .font(.system(size: 15))
                .accessibilityLabel(done ? "Done" : (optional ? "Optional, not done" : "Not done"))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !done { action() }
        }
    }

    private func refresh() {
        readiness = controller.readiness
    }
}
