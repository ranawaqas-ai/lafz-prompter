import Foundation
import Testing
@testable import LafzPrompter

struct AnswerHistoryTests {
    private func store() -> (AnswerHistoryStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).sqlite")
        return (AnswerHistoryStore(url: url), url)
    }

    private func record(_ question: String, session: String = "s1", at seconds: Double) -> AnswerRecord {
        AnswerRecord(id: 0, sessionID: session, askedAt: Date(timeIntervalSince1970: seconds),
                     question: question, answer: "", model: "claude-haiku-5-5", latency: nil, interrupted: false)
    }

    @Test func insertsUpdatesAndReadsNewestFirst() {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }

        var first = store.insert(record("What's a heap?", at: 100))
        let second = store.insert(record("Why O(log n)?", at: 200))
        #expect(first.id != second.id)

        first.answer = "A tree where each parent is smaller than its children."
        first.latency = 1.5
        first.interrupted = true
        store.update(first)

        let recent = store.recent()
        #expect(recent.map(\.question) == ["Why O(log n)?", "What's a heap?"])
        #expect(recent.last?.answer == first.answer)
        #expect(recent.last?.latency == 1.5)
        #expect(recent.last?.interrupted == true)
        #expect(recent.first?.latency == nil)
        #expect(store.count() == 2)
    }

    @Test func survivesReopeningTheFile() {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        store.insert(record("Quote's \"escaping\" and café, ok?", at: 1))

        let reopened = AnswerHistoryStore(url: url)
        #expect(reopened.recent().first?.question == "Quote's \"escaping\" and café, ok?")
    }

    @Test func deleteAllEmptiesTheStore() {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        store.insert(record("a", at: 1))
        store.deleteAll()
        #expect(store.count() == 0)
        #expect(store.recent().isEmpty)
    }
}
