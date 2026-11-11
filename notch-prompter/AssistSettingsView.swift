import SwiftUI

// MARK: - Assist Tab
struct AssistTabView: View {
    @ObservedObject var settings: CallAssistSettings

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Call Assist (experimental)")
                        .font(.system(size: 13, weight: .medium))
                    Text("Listens to both sides of a call and shows a suggested answer in the prompter when the other person asks a question. Audio stays on this Mac; the transcript, your instructions and knowledge base are sent to the provider below. No audio or transcript is saved. Check that the people on the call are fine with being transcribed.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Divider()

                ProviderSection(settings: settings)

                Divider()

                InstructionsSection(settings: settings)
                    .disabled(!settings.isAvailable)
                    .opacity(settings.isAvailable ? 1 : 0.5)
            }
            .padding(16)
        }
    }
}

private struct ProviderSection: View {
    @ObservedObject var settings: CallAssistSettings
    @State private var keyDraft = ""
    @State private var keyError: String?
    @State private var testOutput = ""
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI provider")
                .font(.system(size: 13, weight: .medium))

            Picker("Provider", selection: $settings.provider) {
                ForEach(AssistProvider.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: settings.provider) { resetTest() }

            if settings.isAvailable {
                HStack {
                    Label("\(settings.provider.displayName) key saved in the Keychain", systemImage: "key.fill")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Remove", role: .destructive) {
                        settings.removeKey()
                        resetTest()
                    }
                }
            } else {
                HStack {
                    SecureField("\(settings.provider.displayName) API key", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Call Assist stays off until a key is saved.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let keyError {
                Text(keyError).font(.system(size: 11)).foregroundStyle(.red)
            }

            Group {
                HStack {
                    Text("Model").frame(width: 110, alignment: .leading)
                    TextField(settings.provider.defaultModel, text: Binding(
                        get: { settings.model }, set: { settings.model = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Context window").frame(width: 110, alignment: .leading)
                    TextField("tokens", value: Binding(
                        get: { settings.contextWindow }, set: { settings.contextWindow = $0 }),
                              format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Text("tokens").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Button(testTask == nil ? "Test" : "Testing…") { runTest() }
                        .disabled(testTask != nil)
                    Text(testOutput)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(size: 12))
            .disabled(!settings.isAvailable)
            .opacity(settings.isAvailable ? 1 : 0.5)
        }
    }

    private func saveKey() {
        do {
            try settings.saveKey(keyDraft)
            keyDraft = ""
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
    }

    private func runTest() {
        guard let client = settings.makeClient() else { return }
        testOutput = ""
        let request = AnswerRequest(
            instructions: "Reply in one short sentence.",
            knowledge: "",
            transcript: "",
            question: "Say that the connection works.")
        testTask = Task { @MainActor in
            let start = Date()
            do {
                for try await text in client.stream(request) {
                    testOutput += text
                }
                testOutput += String(format: "  (%.1f s)", Date().timeIntervalSince(start))
            } catch is CancellationError {
            } catch {
                testOutput = "Error: \(error.localizedDescription)"
            }
            testTask = nil
        }
    }

    private func resetTest() {
        testTask?.cancel()
        testTask = nil
        testOutput = ""
        keyError = nil
        keyDraft = ""
    }
}

private struct InstructionsSection: View {
    @ObservedObject var settings: CallAssistSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Instructions")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Reset to default") {
                    settings.instructions = CallAssistSettings.defaultInstructions
                }
                .disabled(settings.instructions == CallAssistSettings.defaultInstructions)
            }
            Text("What you want from the assistant: tone, length, who you are, what the call is about.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextEditor(text: $settings.instructions)
                .font(.system(size: 12))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
