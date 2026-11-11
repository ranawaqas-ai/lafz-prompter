import Foundation

/// One call's answers, oldest first, which one is still streaming, and which
/// one the prompter shows. A plain value: Call Assist decides when things
/// happen, this decides what they do to the list.
struct AnswerTimeline: Equatable {
    private(set) var answers: [AnswerRecord] = []
    /// The answer shown when the user has gone back; nil follows the newest.
    private(set) var viewing: Int?
    /// The answer still streaming, as an index into answers.
    private(set) var streamingIndex: Int?

    var displayedIndex: Int? {
        answers.isEmpty ? nil : min(viewing ?? answers.count - 1, answers.count - 1)
    }

    var displayed: AnswerRecord? { displayedIndex.map { answers[$0] } }

    /// Adds an answer that starts streaming, and shows it. The answer it
    /// replaces, if that one was still streaming, comes back marked as cut
    /// short so it can be saved that way.
    mutating func begin(_ record: AnswerRecord) -> (index: Int, cutShort: AnswerRecord?) {
        let cutShort = finishStreaming(interrupted: true)
        answers.append(record)
        streamingIndex = answers.count - 1
        viewing = nil
        return (answers.count - 1, cutShort)
    }

    mutating func append(_ text: String, at index: Int) {
        guard answers.indices.contains(index) else { return }
        answers[index].answer += text
    }

    mutating func replaceAnswer(with text: String, at index: Int) {
        guard answers.indices.contains(index) else { return }
        answers[index].answer = text
    }

    mutating func setLatency(_ latency: TimeInterval, at index: Int) {
        guard answers.indices.contains(index) else { return }
        answers[index].latency = latency
    }

    /// Ends the streaming answer and returns it, so it can be saved; nil when
    /// nothing is streaming.
    mutating func finishStreaming(interrupted: Bool) -> AnswerRecord? {
        guard let index = streamingIndex, answers.indices.contains(index) else { return nil }
        answers[index].interrupted = interrupted
        streamingIndex = nil
        return answers[index]
    }

    /// Shows the answer before the one on screen.
    mutating func showPrevious() {
        guard let index = displayedIndex, index > 0 else { return }
        viewing = index - 1
    }

    /// Shows the answer after the one on screen; past the newest, follows it.
    mutating func showNext() {
        guard let index = displayedIndex, index < answers.count - 1 else { return }
        viewing = index + 1 == answers.count - 1 ? nil : index + 1
    }
}
