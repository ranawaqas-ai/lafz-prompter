import AVFoundation
import CoreGraphics
import Combine
import Dependencies
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
            updateShortcuts()
        }
    }
    @Published private(set) var transcript: [Utterance] = []
    /// This session's answers, oldest first, including ones a newer question
    /// cut short. Each is also saved to the history file when that is on.
    @Published private(set) var answers: [AnswerRecord] = []
    /// The answer being shown when the user has gone back; nil follows the newest.
    @Published private(set) var viewing: Int?

    var displayedIndex: Int? { answers.isEmpty ? nil : min(viewing ?? answers.count - 1, answers.count - 1) }
    var question: String { displayedIndex.map { answers[$0].question } ?? "" }
    var answer: String { displayedIndex.map { answers[$0].answer } ?? "" }
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
    @Dependency(\.micPermission) private var micPermission
    @Dependency(\.utteranceSource) private var utteranceSource
    @Dependency(\.screenCapture) private var screenCapture
    @Dependency(\.globalShortcuts) private var shortcuts
    /// Every answer, kept when Save history is on. Settings reads it too.
    @Dependency(\.answerHistory) var history
    private var listener: UtteranceSource?
    private var knowledge = ""
    /// Made once per session, so the Keychain is read at start and never mid-call.
    private var client: AnswerProvider?
    private var noticeTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var sessionID = ""
    /// The answer still streaming, as an index into answers.
    private var streamingIndex: Int?
    private lazy var screen = screenCapture.make()
    /// Why screenshots are not being attached, for the Assist tab.
    @Published private(set) var screenProblem: String?
    private let log = callAssistLog
    private static let transcriptSpan: TimeInterval = 5 * 60

    init(settings: CallAssistSettings) {
        self.settings = settings
        keyReady = settings.isAvailable
        updateShortcuts()
        // A key saved or removed, or another provider picked, in Settings.
        keyTask = Task { [weak self, settings] in
            for await ready in Observations({ settings.isAvailable }) {
                guard let self else { return }
                if ready != self.keyReady {
                    self.keyReady = ready
                    self.updateShortcuts()
                }
            }
        }
    }

    /// Follows the app's "Global keyboard shortcuts" setting.
    var shortcutsEnabled = true {
        didSet { updateShortcuts() }
    }
    /// Whether the selected provider has a key, so a session could start.
    private var keyReady = false
    private var keyTask: Task<Void, Never>?

    /// ⌃⌥A is taken only once a session could start; the keys that act on a
    /// session only while one runs.
    private func updateShortcuts() {
        shortcuts.set([.assistToggle: { [weak self] in self?.toggle() }],
                      on: shortcutsEnabled && (keyReady || isActive))
        shortcuts.set([
            .answerNow: { [weak self] in self?.answerNow() },
            .solveScreen: { [weak self] in self?.solveScreen() },
            .previousAnswer: { [weak self] in self?.showPrevious() },
            .nextAnswer: { [weak self] in self?.showNext() },
        ], on: shortcutsEnabled && isActive)
    }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard settings.isAvailable, state == .idle else { return }
        state = .starting
        error = nil
        transcript = []
        answers = []
        viewing = nil
        streamingIndex = nil
        sessionID = UUID().uuidString
        lastLatency = nil
        clearNotice()

        listenTask = Task {
            do {
                guard await micPermission.request() else {
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

                let listener = utteranceSource.make()
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
        finishStreaming(interrupted: true)
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

    /// Shows the answer before the one on screen.
    func showPrevious() {
        guard let index = displayedIndex, index > 0 else { return }
        viewing = index - 1
    }

    /// Shows the answer after the one on screen; past the newest, follows it.
    func showNext() {
        guard let index = displayedIndex, index < answers.count - 1 else { return }
        viewing = index + 1 == answers.count - 1 ? nil : index + 1
    }

    /// Saves the streaming answer as it stands and stops tracking it.
    private func finishStreaming(interrupted: Bool) {
        guard let index = streamingIndex, answers.indices.contains(index) else { return }
        answers[index].interrupted = interrupted
        save(answers[index])
        streamingIndex = nil
    }

    private func save(_ record: AnswerRecord) {
        guard settings.saveHistory, record.id != 0 else { return }
        history.update(record)
    }

    private func answer(_ question: String, endedAt: Date, screenshot: Data?) {
        guard let client else { return }
        // The one being replaced stays in the history, marked as cut short.
        finishStreaming(interrupted: true)
        answerTask?.cancel()
        var record = AnswerRecord(id: 0, sessionID: sessionID, askedAt: Date(), question: question,
                                  answer: "", model: settings.model.id, latency: nil, interrupted: false)
        if settings.saveHistory { record = history.insert(record) }
        answers.append(record)
        let index = answers.count - 1
        streamingIndex = index
        viewing = nil
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
                        answers[index].latency = latency
                        log.info("first answer word \(latency, format: .fixed(precision: 2)) s after question ended")
                    }
                    answers[index].answer += text
                }
            } catch {
                guard !Task.isCancelled else { return }
                log.error("answer failed: \(error.localizedDescription, privacy: .public)")
                answers[index].answer = "Could not get an answer: \(error.localizedDescription)"
            }
            guard !Task.isCancelled else {
                log.info("answer superseded by a newer question")
                return
            }
            log.info("answer done, \(self.answers[index].answer.count) characters")
            finishStreaming(interrupted: false)
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
