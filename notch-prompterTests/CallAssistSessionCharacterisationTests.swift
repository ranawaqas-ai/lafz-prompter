import Dependencies
import Foundation
import SnapshotTesting
import Testing
@testable import LafzPrompter

/// Characterisation tests for a Call Assist session, with the mic, the
/// transcriber and the AI provider replaced by scripted fakes. Each scenario
/// is approved as a text file showing what the user would see, what was sent
/// to the provider, and what was saved to the history database.
@MainActor
@Suite(.serialized)
struct CallAssistSessionCharacterisationTests {

    // MARK: Fakes

    // The fakes are used only from the main actor; @unchecked Sendable lets
    // the container's @Sendable factories hand them out.

    /// Stands in for the mic and system audio transcribers.
    final class FakeListener: UtteranceSource, @unchecked Sendable {
        let utterances: AsyncStream<Utterance>
        private let continuation: AsyncStream<Utterance>.Continuation
        init() { (utterances, continuation) = AsyncStream.makeStream() }
        func start() async throws {}
        func stop() async { continuation.finish() }
        func say(_ text: String, as speaker: Speaker = .them) {
            continuation.yield(Utterance(speaker: speaker, text: text, endedAt: Date()))
        }
    }

    /// Answers each request with the next scripted reply and records it.
    final class FakeProvider: AnswerProvider, @unchecked Sendable {
        enum Reply {
            case answer([String])
            /// Sends these pieces and then never finishes, like a slow answer.
            case stall([String])
            case failure(String)
        }
        var replies: [Reply]
        private(set) var requests: [AnswerRequest] = []
        init(_ replies: [Reply]) { self.replies = replies }

        func stream(_ request: AnswerRequest) -> AsyncThrowingStream<String, Error> {
            requests.append(request)
            let reply = replies.isEmpty ? .answer(["(no scripted reply)"]) : replies.removeFirst()
            return AsyncThrowingStream { continuation in
                switch reply {
                case .answer(let pieces):
                    pieces.forEach { continuation.yield($0) }
                    continuation.finish()
                case .stall(let pieces):
                    pieces.forEach { continuation.yield($0) }
                case .failure(let message):
                    continuation.finish(throwing: ProviderError(message: message))
                }
            }
        }
    }

    /// Screen capture holding whatever screenshot or problem the test sets.
    @MainActor
    final class FakeScreen: ScreenCapture {
        var latest: ScreenSnapshotter.Snapshot?
        var problem: String?
        func start() {}
        func stop() {}
        func refresh() async {}
    }

    /// Overrides every service a Call Assist session touches. `keys` are the
    /// providers with an API key saved.
    static func useFakes(_ values: inout DependencyValues, defaults: UserDefaults, keys: Set<AssistProvider>,
                         micAllowed: Bool = true, listener: FakeListener, provider: FakeProvider,
                         history: AnswerHistoryStore, shortcuts: GlobalShortcuts, screen: FakeScreen? = nil) {
        values.settingsStorage = defaults
        values.keychain = KeychainClient(
            hasKey: { keys.contains($0) },
            key: { keys.contains($0) ? "test-key" : nil },
            save: { _, _ in },
            delete: { _ in })
        values.answerClient = AnswerClientFactory(make: { _, _, _ in provider })
        values.micPermission = MicPermissionClient(status: { micAllowed ? .authorized : .denied },
                                                   request: { micAllowed })
        values.utteranceSource = UtteranceSourceClient(make: { listener })
        values.screenCapture = ScreenCaptureClient(make: { screen ?? FakeScreen() })
        values.answerHistory = history
        values.globalShortcuts = shortcuts
    }

    /// One controller wired to fakes, a throwaway settings suite and a
    /// throwaway history file.
    final class Harness {
        let listener = FakeListener()
        let screen = FakeScreen()
        let provider: FakeProvider
        let settings: CallAssistSettings
        let controller: CallAssistSession
        private let suiteName = "lafz-assist-tests-\(UUID().uuidString)"
        private let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).sqlite")

        @MainActor
        init(_ replies: [FakeProvider.Reply] = [], hasKey: Bool = true, micAllowed: Bool = true,
             saveHistory: Bool = true, includeScreen: Bool = false) {
            let provider = FakeProvider(replies)
            self.provider = provider
            let defaults = UserDefaults(suiteName: suiteName)!
            let listener = listener
            let screen = screen
            let historyURL = historyURL
            (settings, controller) = withDependencies {
                CallAssistSessionCharacterisationTests.useFakes(
                    &$0, defaults: defaults, keys: hasKey ? Set(AssistProvider.allCases) : [],
                    micAllowed: micAllowed, listener: listener, provider: provider,
                    history: AnswerHistoryStore(url: historyURL),
                    shortcuts: GlobalShortcuts(registersWithSystem: false), screen: screen)
            } operation: {
                let settings = CallAssistSettings()
                return (settings, CallAssistSession(settings: settings))
            }
            settings.includeScreen = includeScreen
            settings.saveHistory = saveHistory
        }

        deinit {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: historyURL)
        }
    }

    /// Waits for the session to reach a state, polling the main actor.
    private func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting", sourceLocation: sourceLocation)
    }

    private func started(_ harness: Harness) async {
        harness.controller.start()
        await until { harness.controller.state == .listening }
    }

    // MARK: Scenarios

    @Test func aQuestionIsAnsweredAndSaved() async {
        let h = Harness([.answer(["I have ", "five years ", "of Swift."])])
        await started(h)
        h.listener.say("Hi, thanks for joining today.", as: .me)
        h.listener.say("What is your experience with Swift so far?")
        await until { h.controller.answers.first?.answer.hasSuffix("Swift.") == true && h.controller.state == .listening }
        assertSnapshot(of: Self.report(h), as: .lines, named: "answered")
    }

    @Test func aNewQuestionCutsOffTheAnswerBeingStreamed() async {
        let h = Harness([.stall(["Well, the first "]), .answer(["Second answer."])])
        await started(h)
        h.listener.say("What is your experience with Swift so far?")
        await until { h.controller.answers.first?.answer == "Well, the first " }
        h.listener.say("How would you design a rate limiter for an API?")
        await until { h.controller.answers.count == 2 && h.controller.state == .listening }
        assertSnapshot(of: Self.report(h), as: .lines, named: "interrupted")
    }

    @Test func aProviderErrorIsShownAsTheAnswer() async {
        let h = Harness([.failure("rate limited")])
        await started(h)
        h.listener.say("What is your experience with Swift so far?")
        await until { h.controller.answers.first?.answer.isEmpty == false && h.controller.state == .listening }
        assertSnapshot(of: Self.report(h), as: .lines, named: "failed")
    }

    /// Statements are not answered, my own questions are not answered, and my
    /// mic picking up their voice from the speakers is dropped as an echo.
    @Test func statementsMyQuestionsAndEchoesAreNotAnswered() async {
        let h = Harness()
        await started(h)
        h.listener.say("Thanks, that was really great to hear from you.")
        h.listener.say("Thanks, that was really great to hear from you.", as: .me)
        h.listener.say("What is your experience with Swift so far?", as: .me)
        h.listener.say("Okay.")
        try? await Task.sleep(for: .milliseconds(200))
        assertSnapshot(of: Self.report(h), as: .lines, named: "not-answered")
    }

    @Test func goingBackAndForwardThroughAnswers() async {
        let h = Harness([.answer(["First."]), .answer(["Second."])])
        await started(h)
        h.listener.say("What is your experience with Swift so far?")
        await until { h.controller.answers.first?.answer == "First." && h.controller.state == .listening }
        h.listener.say("How would you design a rate limiter for an API?")
        await until { h.controller.answers.count == 2 && h.controller.state == .listening }

        var steps = "start: \(Self.shown(h))\n"
        h.controller.showPrevious(); steps += "previous: \(Self.shown(h))\n"
        h.controller.showPrevious(); steps += "previous again: \(Self.shown(h))\n"
        h.controller.showNext(); steps += "next: \(Self.shown(h))\n"
        h.controller.showNext(); steps += "next again: \(Self.shown(h))\n"
        h.controller.showPrevious()
        h.listener.say("Why did you pick that approach over the others?")
        await until { h.controller.answers.count == 3 }
        steps += "new question while looking back: \(Self.shown(h))"
        assertSnapshot(of: steps, as: .lines, named: "navigation")
    }

    @Test func stoppingMidAnswerSavesItAsCutShort() async {
        let h = Harness([.stall(["Half an "])])
        await started(h)
        h.listener.say("What is your experience with Swift so far?")
        await until { h.controller.answers.first?.answer == "Half an " }
        h.controller.stop()
        assertSnapshot(of: Self.report(h), as: .lines, named: "stopped")
    }

    @Test func withHistoryOffNothingIsSaved() async {
        let h = Harness([.answer(["Kept in memory only."])], saveHistory: false)
        await started(h)
        h.listener.say("What is your experience with Swift so far?")
        await until { h.controller.answers.first?.answer.hasSuffix("only.") == true && h.controller.state == .listening }
        assertSnapshot(of: Self.report(h), as: .lines, named: "history-off")
    }

    @Test func answersCarryTheScreenshotWhenScreenIsOn() async {
        let h = Harness([.answer(["Use a hash map."]), .answer(["Solved."])], includeScreen: true)
        h.screen.latest = ScreenSnapshotter.Snapshot(jpeg: Data(repeating: 7, count: 2048), capturedAt: Date())
        await started(h)
        h.listener.say("How would you solve the problem on your screen?")
        await until { h.controller.answers.first?.answer == "Use a hash map." && h.controller.state == .listening }
        h.controller.solveScreen()
        await until { h.controller.answers.count == 2 && h.controller.answers[1].answer == "Solved." && h.controller.state == .listening }
        assertSnapshot(of: Self.report(h), as: .lines, named: "screenshot")
    }

    @Test func solvingTheScreenWithoutAScreenshotExplainsWhy() async {
        let h = Harness()
        h.screen.problem = "Screen capture is off. Allow Lafz Prompter in System Settings."
        await started(h)
        h.controller.solveScreen()
        await until { h.controller.notice != nil }
        assertSnapshot(of: Self.report(h), as: .lines, named: "no-screenshot")
    }

    @Test func withoutAKeyStartDoesNothing() async {
        let h = Harness(hasKey: false)
        h.controller.start()
        try? await Task.sleep(for: .milliseconds(100))
        assertSnapshot(of: Self.report(h), as: .lines, named: "no-key")
    }

    @Test func withTheMicDeniedStartShowsWhy() async {
        let h = Harness(micAllowed: false)
        h.controller.start()
        await until { h.controller.notice != nil }
        assertSnapshot(of: Self.report(h), as: .lines, named: "mic-denied")
    }

    // MARK: Rendering the session as text

    private static func shown(_ h: Harness) -> String {
        let index = h.controller.displayedIndex.map { "\($0 + 1)/\(h.controller.answers.count)" } ?? "none"
        return "\(index) \"\(h.controller.question)\" following newest: \(h.controller.viewing == nil)"
    }

    static func report(_ h: Harness) -> String {
        let c = h.controller
        var lines = [
            "state: \(c.state)",
            "notice: \(c.notice ?? "none")",
            "error: \(c.error ?? "none")",
            "transcript:",
        ]
        lines += c.transcript.map { "  \($0.speaker.rawValue): \($0.text)" }
        lines.append("answers on screen:")
        for (i, a) in c.answers.enumerated() {
            lines.append("  [\(i + 1)] Q: \(a.question)")
            lines.append("      A: \(a.answer)")
            lines.append("      model \(a.model), latency \(a.latency == nil ? "none" : "measured"), cut short \(a.interrupted), saved \(a.id != 0)")
        }
        lines.append("requests to the provider:")
        for (i, r) in h.provider.requests.enumerated() {
            lines.append("  [\(i + 1)] question: \(r.question)")
            lines.append("      screenshot: \(r.screenshot != nil), knowledge: \(r.knowledge.isEmpty ? "none" : "\(r.knowledge.count) chars"), ends with formatting rule: \(r.instructions.hasSuffix(AnswerFormatting.formattingRule))")
            lines += r.userMessage.split(separator: "\n", omittingEmptySubsequences: false).map { "      | \($0)" }
        }
        lines.append("history rows:")
        for row in c.history.recent().reversed() {
            lines.append("  Q: \(row.question) | A: \(row.answer) | cut short \(row.interrupted)")
        }
        return lines.joined(separator: "\n")
    }
}
