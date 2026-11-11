import Foundation
import Testing
@testable import LafzPrompter

struct AnswerTimelineTests {
    private func record(_ question: String, id: Int64 = 0) -> AnswerRecord {
        AnswerRecord(id: id, sessionID: "s", askedAt: Date(timeIntervalSince1970: 0), question: question,
                     answer: "", model: "m", latency: nil, interrupted: false)
    }

    @Test func aNewAnswerStreamsAndIsShown() {
        var timeline = AnswerTimeline()
        let (index, cutShort) = timeline.begin(record("Q1"))
        #expect(index == 0)
        #expect(cutShort == nil)
        timeline.append("Hel", at: index)
        timeline.append("lo", at: index)
        timeline.setLatency(1.5, at: index)
        #expect(timeline.displayed?.answer == "Hello")
        #expect(timeline.displayed?.latency == 1.5)
        #expect(timeline.streamingIndex == 0)
    }

    @Test func aNewAnswerCutsShortTheOneStillStreaming() {
        var timeline = AnswerTimeline()
        let first = timeline.begin(record("Q1", id: 7)).index
        timeline.append("Half", at: first)
        let (second, cutShort) = timeline.begin(record("Q2"))
        #expect(cutShort?.id == 7)
        #expect(cutShort?.answer == "Half")
        #expect(cutShort?.interrupted == true)
        #expect(timeline.answers[first].interrupted)
        #expect(timeline.streamingIndex == second)
    }

    @Test func finishingReturnsTheAnswerOnceAndNotAfterwards() {
        var timeline = AnswerTimeline()
        _ = timeline.begin(record("Q1"))
        #expect(timeline.finishStreaming(interrupted: false)?.interrupted == false)
        #expect(timeline.finishStreaming(interrupted: true) == nil)
        #expect(timeline.answers[0].interrupted == false)
    }

    @Test func goingBackAndForwardStopsAtTheEndsAndFollowsTheNewest() {
        var timeline = AnswerTimeline()
        for question in ["Q1", "Q2", "Q3"] {
            _ = timeline.begin(record(question))
            _ = timeline.finishStreaming(interrupted: false)
        }
        #expect(timeline.displayedIndex == 2)
        timeline.showPrevious(); timeline.showPrevious(); timeline.showPrevious()
        #expect(timeline.displayedIndex == 0)
        timeline.showNext()
        #expect(timeline.viewing == 1)
        timeline.showNext()
        #expect(timeline.viewing == nil)
        #expect(timeline.displayedIndex == 2)
        timeline.showPrevious()
        _ = timeline.begin(record("Q4"))
        #expect(timeline.viewing == nil)
        #expect(timeline.displayed?.question == "Q4")
    }

    @Test func updatesToAMissingIndexAreIgnored() {
        var timeline = AnswerTimeline()
        timeline.append("x", at: 3)
        timeline.replaceAnswer(with: "x", at: 3)
        timeline.setLatency(1, at: 3)
        #expect(timeline == AnswerTimeline())
        #expect(timeline.displayedIndex == nil)
    }
}
