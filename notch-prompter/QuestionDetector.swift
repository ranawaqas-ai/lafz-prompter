import Foundation

/// Decides when the other person has asked something worth answering, and
/// what text to answer. Pure functions over the transcript.
enum QuestionDetector {
    /// Utterances of theirs further back than this are not part of the question.
    static let window: TimeInterval = 30
    static let maxUtterances = 3

    /// Questions that often end in a full stop, e.g. "Tell me about your role."
    private static let askingPhrases = [
        "tell me about", "walk me through", "talk me through", "can you", "could you",
        "would you", "i'd like to hear", "i would like to hear",
    ]
    /// Verbs interviewers open a task with, e.g. "Take an example array and
    /// step through your code." A sentence starting with one is a prompt to
    /// answer when it is long enough to be a task, not "Take your time".
    private static let promptVerbs: Set<String> = [
        "explain", "describe", "walk", "step", "state", "write", "implement", "show",
        "design", "take", "give", "tell", "talk", "trace", "compare", "analyze", "analyse",
        "optimize", "optimise", "solve", "code", "list", "define", "discuss", "consider",
        "suppose", "imagine", "estimate", "calculate", "find", "return", "modify", "extend",
        "refactor", "debug", "fix", "add", "handle", "test", "prove", "derive", "outline",
        "summarize", "summarise", "share", "elaborate", "justify", "rewrite", "convert",
    ]
    private static let minimumPromptWords = 5

    /// Tags that turn a statement into a rhetorical check, not a question.
    private static let tags: Set<String> = ["right", "yeah", "okay", "ok", "you know", "correct", "no", "huh"]

    /// Whether one utterance reads as a question to answer. The transcriber
    /// punctuates questions, so a real question mark is the main signal.
    static func isQuestion(_ text: String) -> Bool {
        if questionSentences(in: text).contains(where: { !isTag($0) }) { return true }
        let lower = text.lowercased()
        if askingPhrases.contains(where: lower.contains) { return true }
        return sentences(in: text).contains(where: isPrompt)
    }

    /// "Step through your code line by line." opens with a task verb and is
    /// long enough to be a task.
    private static func isPrompt(_ sentence: String) -> Bool {
        let words = sentence.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" })
        guard words.count >= minimumPromptWords, let first = words.first else { return false }
        // "Let's" and "now" often lead the verb: "Now, explain how it scales."
        let verb = ["now", "so", "okay", "ok", "next", "please", "and", "then", "let's", "lets"].contains(String(first))
            ? words.dropFirst().first.map(String.init) ?? "" : String(first)
        return promptVerbs.contains(verb)
    }

    private static func sentences(in text: String) -> [String] {
        text.split(whereSeparator: { ".!?".contains($0) }).map(String.init)
    }

    /// The question to answer when `latest` has just arrived, or nil. The text
    /// includes their lead-in statements, e.g. "We use Postgres. How would you
    /// scale it?", so the answer has the context.
    static func question(afterNew latest: Utterance, in transcript: [Utterance]) -> String? {
        guard latest.speaker == .them, isQuestion(latest.text) else { return nil }
        return recentTurn(endingAt: latest, in: transcript)
    }

    /// Their latest run of utterances, for the "answer now" shortcut.
    static func lastTurn(in transcript: [Utterance]) -> String? {
        guard let latest = transcript.last(where: { $0.speaker == .them }) else { return nil }
        return recentTurn(endingAt: latest, in: transcript)
    }

    /// Their consecutive utterances up to `latest`, stopping at anything the
    /// user said, the time window, or the utterance cap.
    private static func recentTurn(endingAt latest: Utterance, in transcript: [Utterance]) -> String {
        var parts: [String] = []
        for utterance in transcript.reversed() where utterance.endedAt <= latest.endedAt {
            if utterance.speaker == .me { break }
            if latest.endedAt.timeIntervalSince(utterance.endedAt) > window || parts.count == maxUtterances { break }
            parts.insert(utterance.text, at: 0)
        }
        return parts.isEmpty ? latest.text : parts.joined(separator: " ")
    }

    private static func questionSentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".!".contains(character) { current = "" }
            if character == "?" {
                result.append(current)
                current = ""
            }
        }
        return result
    }

    /// "Right?" or "..., right?": the clause after the last comma is a tag.
    private static func isTag(_ sentence: String) -> Bool {
        let clause = sentence.split(separator: ",").last.map(String.init) ?? sentence
        let words = clause.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
        return tags.contains(words)
    }

    /// True when a mic utterance is the speakers' sound of their utterance
    /// picked up again (no headphones). Those are dropped from the transcript.
    static func isEcho(_ mine: Utterance, of transcript: [Utterance]) -> Bool {
        guard mine.speaker == .me else { return false }
        let words = wordSet(mine.text)
        guard !words.isEmpty else { return false }
        return transcript.contains { theirs in
            guard theirs.speaker == .them, abs(theirs.endedAt.timeIntervalSince(mine.endedAt)) < 3 else { return false }
            let other = wordSet(theirs.text)
            let overlap = Double(words.intersection(other).count) / Double(words.union(other).count)
            return overlap >= 0.6
        }
    }

    private static func wordSet(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }
}
