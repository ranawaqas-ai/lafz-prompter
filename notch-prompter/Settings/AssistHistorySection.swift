import SwiftUI

/// Past questions and answers from the history file, newest first, with
/// a switch to stop saving and a way to delete everything.
struct HistorySection: View {
    @Bindable var settings: CallAssistSettings
    let controller: CallAssistSession
    @State private var records: [AnswerRecord] = []
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Show File") {
                    NSWorkspace.shared.activateFileViewerSelecting([AnswerHistoryStore.defaultURL])
                }
                Button("Delete All…", role: .destructive) { confirmDelete = true }
                    .disabled(records.isEmpty)
            }
            Toggle("Save questions and answers on this Mac", isOn: $settings.saveHistory)
                .font(.system(size: 12))
            Text("Kept in a SQLite file in Application Support so you can read an answer again after a new question replaces it. In the prompter, ⌃⌥[ and ⌃⌥] step through this call's answers.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if records.isEmpty {
                Text("No saved answers yet.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(records) { record in
                            HistoryRow(record: record)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .onAppear(perform: reload)
        // Refresh as answers finish during a call.
        .onChange(of: controller.state) { reload() }
        .confirmationDialog("Delete all saved questions and answers?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) {
                controller.history.deleteAll()
                reload()
            }
        }
    }

    private func reload() {
        records = controller.history.recent()
    }
}

private struct HistoryRow: View {
    let record: AnswerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(record.askedAt, format: .dateTime.day().month().hour().minute())
                Text(record.model)
                if let latency = record.latency {
                    Text(String(format: "%.1f s", latency))
                }
                if record.interrupted {
                    Text("cut short")
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            Text(record.question)
                .font(.system(size: 11, weight: .medium))
                .textSelection(.enabled)
            Text(record.answer.isEmpty ? "No answer." : record.answer)
                .font(.system(size: 11))
                .textSelection(.enabled)
        }
    }
}
