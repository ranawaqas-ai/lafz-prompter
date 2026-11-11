import Foundation
import Testing
@testable import LafzPrompter

struct QuestionDetectorTests {
    @Test(arguments: [
        "Can you tell me about the last project you shipped?",
        "What would you do differently next time?",
        "Walk me through how you would design a rate limiter.",
        "Tell me about a time you disagreed with your manager.",
        "We use Postgres today. How would you scale it?",
        "It's slow, right? Why do you think that is?",
    ])
    func questionsAreDetected(text: String) {
        #expect(QuestionDetector.isQuestion(text))
    }

    @Test(arguments: [
        "Thanks, that makes sense.",
        "We shipped it last week, right?",
        "Right?",
        "Okay.",
        "Do that tomorrow.",
        "",
    ])
    func statementsAndTagsAreNot(text: String) {
        #expect(!QuestionDetector.isQuestion(text))
    }

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func them(_ text: String, at seconds: Double) -> Utterance {
        Utterance(speaker: .them, text: text, endedAt: t0.addingTimeInterval(seconds))
    }
    private func me(_ text: String, at seconds: Double) -> Utterance {
        Utterance(speaker: .me, text: text, endedAt: t0.addingTimeInterval(seconds))
    }

    @Test func questionIncludesTheirLeadInButNotMyLastTurn() {
        let transcript = [
            me("I worked on payments.", at: 0),
            them("Interesting.", at: 5),
            them("We have a lot of traffic.", at: 8),
            them("How would you shard the database?", at: 11),
        ]
        let q = QuestionDetector.question(afterNew: transcript.last!, in: transcript)
        #expect(q == "Interesting. We have a lot of traffic. How would you shard the database?")
    }

    @Test func statementAfterAQuestionDoesNotTriggerAgain() {
        let transcript = [them("What's your background?", at: 0), them("Take your time.", at: 2)]
        #expect(QuestionDetector.question(afterNew: transcript.last!, in: transcript) == nil)
    }

    @Test func myUtterancesNeverTrigger() {
        let transcript = [me("What do you mean?", at: 0)]
        #expect(QuestionDetector.question(afterNew: transcript[0], in: transcript) == nil)
    }

    @Test func oldUtterancesFallOutOfTheWindow() {
        let transcript = [them("Earlier context.", at: 0), them("Why?", at: 100)]
        #expect(QuestionDetector.question(afterNew: transcript.last!, in: transcript) == "Why?")
    }

    @Test func lastTurnIsTheirMostRecentRun() {
        let transcript = [them("So.", at: 0), them("Your thoughts", at: 1), me("Hmm", at: 2)]
        #expect(QuestionDetector.lastTurn(in: transcript) == "So. Your thoughts")
    }

    @Test func micPickupOfTheSpeakersIsAnEcho() {
        let transcript = [them("Walk me through how you would design a rig limiter.", at: 10)]
        #expect(QuestionDetector.isEcho(me("Walk me through how you would design a rate limiter.", at: 10.05), of: transcript))
        #expect(!QuestionDetector.isEcho(me("I would start with a token bucket.", at: 12), of: transcript))
        #expect(!QuestionDetector.isEcho(me("Walk me through how you would design a rate limiter.", at: 30), of: transcript))
    }
}
