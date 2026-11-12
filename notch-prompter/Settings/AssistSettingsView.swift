import SwiftUI

// MARK: - Assist Tab
struct AssistTabView: View {
    @Environment(CallAssistSettings.self) private var settings
    @Environment(CallAssistSession.self) private var controller

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Call Assist (experimental)")
                        .font(.system(size: 13, weight: .medium))
                    Text("Listens to both sides of a call and shows a suggested answer in the prompter when the other person asks a question. Audio stays on this Mac and is never saved; the transcript, your instructions and knowledge base are sent to the provider below. Questions and answers are kept on this Mac if History is on. Check that the people on the call are fine with being transcribed.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Divider()

                SessionSection(settings: settings, controller: controller)

                Divider()

                ProviderSection(settings: settings)

                Divider()

                Group {
                    InstructionsSection(settings: settings)
                    Divider()
                    KnowledgeSection(settings: settings)
                    Divider()
                    HistorySection(settings: settings, controller: controller)
                }
                .disabled(!settings.isAvailable)
                .opacity(settings.isAvailable ? 1 : 0.5)
            }
            .padding(16)
        }
    }
}

private struct ProviderSection: View {
    @Bindable var settings: CallAssistSettings
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
                Picker("Model", selection: Binding(
                    get: { settings.model }, set: { settings.model = $0; resetTest() })) {
                    ForEach(settings.provider.models) { Text($0.name).tag($0) }
                }
                Text("Context window: \(settings.contextWindow.formatted()) tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
                var firstText: TimeInterval?
                for try await text in client.stream(request) {
                    guard !Task.isCancelled else { return }
                    if firstText == nil { firstText = Date().timeIntervalSince(start) }
                    testOutput += text
                }
                guard !Task.isCancelled else { return }
                testOutput += String(format: "  (first text after %.1f s)", firstText ?? 0)
            } catch {
                guard !Task.isCancelled else { return }
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
    @Bindable var settings: CallAssistSettings

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

private struct KnowledgeSection: View {
    @Bindable var settings: CallAssistSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Knowledge base")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Add Files…") { choose(folders: false) }
                Button("Add Folder…") { choose(folders: true) }
            }
            Text("Documents (text, Markdown, PDF) or a code folder. Folders in a git repo follow its .gitignore; binary files are skipped. Everything is sent with each question and cached by the provider.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ForEach(settings.knowledgeSources, id: \.self) { url in
                HStack {
                    Image(systemName: url.hasDirectoryPath ? "folder" : "doc")
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                    Spacer()
                    Text(detail(for: url))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button {
                        settings.removeKnowledgeSource(url)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.system(size: 12))
            }

            HStack {
                Text("Total")
                Spacer()
                if let tokens = settings.knowledgeTokens {
                    Text("≈\(tokens.formatted()) of \(settings.contextWindow.formatted()) tokens")
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.system(size: 12, weight: .medium))

            if let overflow = settings.knowledgeOverflowMessage {
                Text(overflow)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private func detail(for url: URL) -> String {
        guard let source = settings.knowledgeSummary?.first(where: { $0.url == url }) else { return "counting…" }
        if let error = source.error { return error }
        let files = source.fileCount == 1 ? "1 file" : "\(source.fileCount) files"
        return "\(files), ≈\(source.tokens.formatted()) tokens"
    }

    private func choose(folders: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folders
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        settings.addKnowledgeSources(panel.urls)
    }
}

/// Start and stop, plus the live transcript so capture problems show while testing.
private struct SessionSection: View {
    @Bindable var settings: CallAssistSettings
    let controller: CallAssistSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    controller.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text(controller.isActive ? "Stop Call Assist" : "Start Call Assist")
                        KeycapLabel(GlobalShortcuts.Shortcut.assistToggle.label)
                    }
                }
                .keyboardShortcut("a", modifiers: [.control, .option])
                .disabled(!settings.isAvailable || settings.knowledgeOverflowMessage != nil)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("⌃⌥A starts or stops it. ⌃⌥Return answers their last words when no question was detected. ⌃⌥S answers from what is on screen. The prompter is hidden from screen sharing while it runs.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Toggle("Include a screenshot with each answer", isOn: $settings.includeScreen)
                .font(.system(size: 12))
                .disabled(controller.isActive)
            Text("Takes a screenshot of the display you are working on every 2 seconds and keeps only the newest, in memory. It is sent with each answer, so everything on that display at the time goes to the provider.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let problem = controller.screenProblem {
                Text(problem).font(.system(size: 11)).foregroundStyle(.orange)
            }
            if let error = controller.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
            if controller.isActive {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(controller.transcript.suffix(6).enumerated()), id: \.offset) { _, line in
                        Text("\(Text(line.speaker == .me ? "Me: " : "Them: ").bold())\(line.text)")
                            .font(.system(size: 11))
                            .foregroundStyle(line.speaker == .me ? .secondary : .primary)
                    }
                    if controller.transcript.isEmpty {
                        Text("Nothing heard yet.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var status: String {
        switch controller.state {
        case .idle: return settings.isAvailable ? "Off" : "Save an API key below to use Call Assist."
        case .starting: return "Starting…"
        case .listening, .answering:
            guard let latency = controller.lastLatency else { return "Listening" }
            return String(format: "Listening. Last answer started %.1f s after the question.", latency)
        }
    }
}
