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
        "use", "pick", "choose", "run", "try", "assume", "go", "build", "draw", "sketch",
        "identify", "check", "verify", "improve", "reduce", "count", "sort", "reverse",
    ]
    /// Requests that put the verb later: "I need you to pick an example input".
    private static let requestPhrases = [
        "need you to", "want you to", "like you to", "i'd like to see", "i would like to see",
        "go ahead and", "let's see", "let me see", "show me", "i'm curious", "help me understand",
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
        if requestPhrases.contains(where: lower.contains), wordCount(text) >= minimumPromptWords { return true }
        // Any clause that opens with a task verb, so "Take an example array,
        // step through your code" counts as well as "Step through your code".
        guard wordCount(text) >= minimumPromptWords else { return false }
        return clauses(in: text).contains(where: opensWithTaskVerb)
    }

    /// Words that often come before the verb: "Now, explain", "and then state".
    private static let leadIns: Set<String> = ["now", "so", "okay", "ok", "next", "please", "and", "then", "also", "first", "finally", "let's", "lets"]

    private static func opensWithTaskVerb(_ clause: String) -> Bool {
        let words = clause.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        guard let verb = words.first(where: { !leadIns.contains($0) }) else { return false }
        return promptVerbs.contains(verb)
    }

    /// Clauses split at sentence ends, commas, semicolons and " and ".
    private static func clauses(in text: String) -> [String] {
        text.replacingOccurrences(of: " and ", with: ",")
            .split(whereSeparator: { ".!?,;:".contains($0) })
            .map(String.init)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).count
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
