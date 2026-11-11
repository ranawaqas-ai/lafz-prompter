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

    @Published private(set) var state: State = .idle {
        didSet {
            if state != oldValue { callAssistLog.info("state: \(String(describing: self.state), privacy: .public)") }
        }
    }
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
    private var solveScreenHotKey: HotKey?
    private let screen = ScreenSnapshotter()
    /// Why screenshots are not being attached, for the Assist tab.
    @Published private(set) var screenProblem: String?
    private let log = callAssistLog
    private static let transcriptSpan: TimeInterval = 5 * 60

    init(settings: CallAssistSettings) {
        self.settings = settings
        toggleHotKey = HotKey(key: .a, modifiers: [.control, .option])
        toggleHotKey?.keyDownHandler = { [weak self] in self?.toggle() }
        answerNowHotKey = HotKey(key: .return, modifiers: [.control, .option])
        answerNowHotKey?.keyDownHandler = { [weak self] in self?.answerNow() }
        solveScreenHotKey = HotKey(key: .s, modifiers: [.control, .option])
        solveScreenHotKey?.keyDownHandler = { [weak self] in self?.solveScreen() }
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
                if settings.includeScreen { screen.start() }
                warmCache()
                for await utterance in listener.utterances {
                    receive(utterance)
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                log.error("could not start: \(error.localizedDescription, privacy: .public)")
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
        screen.stop()
        screenProblem = nil
        knowledge = ""
        client = nil
        state = .idle
    }

    /// Answers their latest turn whether or not it read as a question.
    func answerNow() {
        guard isActive, let turn = QuestionDetector.lastTurn(in: transcript),
              let endedAt = transcript.last(where: { $0.speaker == .them })?.endedAt else { return }
        answer(turn, endedAt: endedAt, screenshot: currentScreenshot())
    }

    /// Answers from a fresh screenshot alone, for a problem that is shown but
    /// never read out. Works even with screenshots off for spoken questions.
    func solveScreen() {
        guard isActive else { return }
        Task {
            await screen.refresh()
            screenProblem = screen.problem
            guard let shot = screen.latest?.jpeg else {
                show(notice: screen.problem ?? "Could not capture the screen.")
                return
            }
            answer("Answer or solve what is on my screen.", endedAt: Date(), screenshot: shot)
        }
    }

    private func currentScreenshot() -> Data? {
        guard settings.includeScreen else { return nil }
        screenProblem = screen.problem
        return screen.latest?.jpeg
    }

    private func receive(_ utterance: Utterance) {
        if QuestionDetector.isEcho(utterance, of: transcript) {
            log.info("dropped mic echo of the speakers: \(utterance.text, privacy: .public)")
            return
        }
        if utterance.speaker == .them {
            // The mic copy of their words can land first.
            transcript.removeAll { QuestionDetector.isEcho($0, of: [utterance]) }
        }
        transcript.append(utterance)
        transcript.removeAll { utterance.endedAt.timeIntervalSince($0.endedAt) > Self.transcriptSpan }

        if let question = QuestionDetector.question(afterNew: utterance, in: transcript) {
            log.info("question detected: \(question, privacy: .public)")
            answer(question, endedAt: utterance.endedAt, screenshot: currentScreenshot())
        } else if utterance.speaker == .them {
            log.info("not a question, no answer: \(utterance.text, privacy: .public)")
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

    private func answer(_ question: String, endedAt: Date, screenshot: Data?) {
        answerTask?.cancel()
        guard let client else { return }
        self.question = question
        answer = ""
        state = .answering
        let request = AnswerRequest(
            instructions: settings.instructions + "\n\n" + AnswerFormatting.formattingRule,
            knowledge: knowledge,
            transcript: transcriptText(),
            question: question,
            screenshot: screenshot)

        log.info("asking \(self.settings.provider.displayName, privacy: .public) \(self.settings.model.id, privacy: .public): screenshot \(screenshot.map { "\($0.count / 1024) KB" } ?? "none", privacy: .public), knowledge \(self.knowledge.count / 4) tokens, transcript \(self.transcript.count) lines")
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
                log.error("answer failed: \(error.localizedDescription, privacy: .public)")
                answer = "Could not get an answer: \(error.localizedDescription)"
            }
            guard !Task.isCancelled else {
                log.info("answer superseded by a newer question")
                return
            }
            log.info("answer done, \(self.answer.count) characters")
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
        let request = AnswerRequest(instructions: settings.instructions + "\n\n" + AnswerFormatting.formattingRule, knowledge: knowledge,
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
