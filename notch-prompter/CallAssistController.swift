import AVFoundation
import CoreGraphics
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
    /// A short message shown in the prompter, e.g. why a start failed.
    @Published private(set) var notice: String?
    /// Requests from the scroll shortcuts to move the answer.
    @Published private(set) var scrollNudge = ScrollNudge(delta: 0, sequence: 0)

    struct ScrollNudge: Equatable {
        let delta: CGFloat
        let sequence: Int
    }

    var isActive: Bool { state != .idle }

    private let settings: CallAssistSettings
    private var listener: CallListener?
    private var knowledge = ""
    /// Made once per session, so the Keychain is read at start and never mid-call.
    private var client: AnswerProvider?
    private var noticeTask: Task<Void, Never>?
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
        clearNotice()

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
                guard let client = settings.makeClient() else {
                    throw CaptureError("No API key saved for \(settings.provider.displayName).")
                }
                self.client = client

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
                show(notice: "Call Assist could not start: \(error.localizedDescription)")
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
        client = nil
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

    func nudgeScroll(by delta: CGFloat) {
        scrollNudge = ScrollNudge(delta: delta, sequence: scrollNudge.sequence + 1)
    }

    private func show(notice: String) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self.notice = nil
        }
    }

    private func clearNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    private func answer(_ question: String, endedAt: Date) {
        answerTask?.cancel()
        guard let client else { return }
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
                    // A cancelled stream ends quietly instead of throwing, so a
                    // superseded answer has to check before touching state.
                    guard !Task.isCancelled else { return }
                    if firstWord {
                        firstWord = false
                        let latency = Date().timeIntervalSince(endedAt)
                        lastLatency = latency
                        log.info("first answer word \(latency, format: .fixed(precision: 2)) s after question ended")
                    }
                    answer += text
                }
            } catch {
                guard !Task.isCancelled else { return }
                answer = "Could not get an answer: \(error.localizedDescription)"
            }
            guard !Task.isCancelled else { return }
            if state == .answering { state = .listening }
        }
    }

    private func transcriptText() -> String {
        transcript.map { "\($0.speaker == .me ? "Me" : "Them"): \($0.text)" }.joined(separator: "\n")
    }

    /// Sends the knowledge base once at the start so the first real question
    /// reads it from the provider's cache.
    private func warmCache() {
        guard !knowledge.isEmpty, let client else { return }
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
