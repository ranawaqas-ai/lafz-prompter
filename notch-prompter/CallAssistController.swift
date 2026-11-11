import AVFoundation
import Combine
import HotKey
import os

/// Runs one Call Assist session: listens, keeps the transcript, detects
/// questions and streams answers for the prompter to show.
@MainActor
final class CallAssistController: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case answering
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: [Utterance] = []
    @Published private(set) var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var error: String?
    /// Seconds from the end of their question to the first answer word, for
    /// the latest answer. The plan's target is a median of 3 s or less.
    @Published private(set) var lastLatency: TimeInterval?

    var isActive: Bool { state != .idle }

    private let settings: CallAssistSettings
    private var listener: CallListener?
    private var knowledge = ""
    private var listenTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var toggleHotKey: HotKey?
    private var answerNowHotKey: HotKey?
    private let log = Logger(subsystem: "space.waqasrana.LafzPrompter", category: "CallAssist")
    private static let transcriptSpan: TimeInterval = 5 * 60

    init(settings: CallAssistSettings) {
        self.settings = settings
        toggleHotKey = HotKey(key: .a, modifiers: [.control, .option])
        toggleHotKey?.keyDownHandler = { [weak self] in self?.toggle() }
        answerNowHotKey = HotKey(key: .return, modifiers: [.control, .option])
        answerNowHotKey?.keyDownHandler = { [weak self] in self?.answerNow() }
    }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard settings.isAvailable, state == .idle else { return }
        state = .starting
        error = nil
        transcript = []
        question = ""
        answer = ""
        lastLatency = nil

        listenTask = Task {
            do {
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw CaptureError("Microphone access is off. Turn it on in System Settings > Privacy & Security > Microphone.")
                }
                let sources = settings.knowledgeSources
                let loaded = await Task.detached(priority: .userInitiated) { KnowledgeBase.load(sources) }.value
                if loaded.tokens > settings.contextWindow {
                    throw CaptureError(settings.knowledgeOverflowMessage
                        ?? "The knowledge base is larger than the model's context window.")
                }
                knowledge = loaded.text

                let listener = CallListener()
                self.listener = listener
                try await listener.start()
                guard state == .starting else { return }
                state = .listening
                warmCache()
                for await utterance in listener.utterances {
                    receive(utterance)
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                stop()
            }
        }
    }

    func stop() {
        answerTask?.cancel()
        answerTask = nil
        listenTask?.cancel()
        listenTask = nil
        if let listener {
            Task { await listener.stop() }
        }
        listener = nil
        knowledge = ""
        state = .idle
    }

    /// Answers their latest turn whether or not it read as a question.
    func answerNow() {
        guard isActive, let turn = QuestionDetector.lastTurn(in: transcript),
              let endedAt = transcript.last(where: { $0.speaker == .them })?.endedAt else { return }
        answer(turn, endedAt: endedAt)
    }

    private func receive(_ utterance: Utterance) {
        if QuestionDetector.isEcho(utterance, of: transcript) { return }
        if utterance.speaker == .them {
            // The mic copy of their words can land first.
            transcript.removeAll { QuestionDetector.isEcho($0, of: [utterance]) }
        }
        transcript.append(utterance)
        transcript.removeAll { utterance.endedAt.timeIntervalSince($0.endedAt) > Self.transcriptSpan }

        if let question = QuestionDetector.question(afterNew: utterance, in: transcript) {
            answer(question, endedAt: utterance.endedAt)
        }
    }

    private func answer(_ question: String, endedAt: Date) {
        answerTask?.cancel()
        guard let client = settings.makeClient() else { return }
        self.question = question
        answer = ""
        state = .answering
        let request = AnswerRequest(
            instructions: settings.instructions,
            knowledge: knowledge,
            transcript: transcriptText(),
            question: question)

        answerTask = Task {
            var firstWord = true
            do {
                for try await text in client.stream(request) {
                    if firstWord {
                        firstWord = false
                        let latency = Date().timeIntervalSince(endedAt)
                        lastLatency = latency
                        log.info("first answer word \(latency, format: .fixed(precision: 2)) s after question ended")
                    }
                    answer += text
                }
            } catch is CancellationError {
                return
            } catch {
                answer = "Could not get an answer: \(error.localizedDescription)"
            }
            if state == .answering { state = .listening }
        }
    }

    private func transcriptText() -> String {
        transcript.map { "\($0.speaker == .me ? "Me" : "Them"): \($0.text)" }.joined(separator: "\n")
    }

    /// Sends the knowledge base once at the start so the first real question
    /// reads it from the provider's cache.
    private func warmCache() {
        guard !knowledge.isEmpty, let client = settings.makeClient() else { return }
        let request = AnswerRequest(instructions: settings.instructions, knowledge: knowledge,
                                    transcript: "", question: "Reply with OK.")
        Task {
            do {
                for try await _ in client.stream(request) { break }
            } catch {
                log.error("cache warm-up failed: \(error.localizedDescription)")
            }
        }
    }
}
