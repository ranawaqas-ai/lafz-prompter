import Foundation
import Testing
@testable import LafzPrompter

struct AnswerFormattingTests {
    @Test func splitsProseAndFencedCode() {
        let answer = """
        I'd use a set.

        ```python
        def has_dupes(xs):
            return len(set(xs)) != len(xs)
        ```
        That is O(n).
        """
        #expect(AnswerFormatting.segments(answer) == [
            .prose("I'd use a set."),
            .code(language: "python", code: "def has_dupes(xs):\n    return len(set(xs)) != len(xs)"),
            .prose("That is O(n)."),
        ])
    }

    @Test func unclosedFenceIsCodeInProgress() {
        let streaming = "Here:\n```swift\nlet x = 1"
        #expect(AnswerFormatting.segments(streaming) == [
            .prose("Here:"),
            .code(language: "swift", code: "let x = 1"),
        ])
    }

    @Test func fenceWithoutLanguageHasNone() {
        #expect(AnswerFormatting.segments("```\nls -la\n```") == [.code(language: nil, code: "ls -la")])
    }

    @Test func plainAnswerIsOneProseSegment() {
        #expect(AnswerFormatting.segments("Just talk.") == [.prose("Just talk.")])
    }
}

struct SyntaxHighlighterTests {
    private func kinds(_ code: String, _ language: String) -> [String: SyntaxHighlighter.Token] {
        var result: [String: SyntaxHighlighter.Token] = [:]
        for (range, token) in SyntaxHighlighter.tokens(in: code, language: language) {
            result[String(code[range])] = token
        }
        return result
    }

    @Test func pythonKeywordsStringsCommentsAndNumbers() {
        let k = kinds(#"def f(x):  # if inside comment"# + "\n    return \"for\" + 42", "python")
        #expect(k["def"] == .keyword)
        #expect(k["return"] == .keyword)
        #expect(k["# if inside comment"] == .comment)
        #expect(k["\"for\""] == .string)
        #expect(k["42"] == .number)
        #expect(k["if"] == nil)
        #expect(k["f"] == .function)
    }

    @Test func swiftTypesAndKeywords() {
        let k = kinds("let cache: [String: Int] = [:] // note", "swift")
        #expect(k["let"] == .keyword)
        #expect(k["String"] == .type)
        #expect(k["Int"] == .type)
        #expect(k["// note"] == .comment)
    }

    @Test func sqlKeywordsIgnoreCase() {
        let k = kinds("SELECT id FROM users WHERE age > 30 -- adults", "sql")
        #expect(k["SELECT"] == .keyword)
        #expect(k["FROM"] == .keyword)
        #expect(k["-- adults"] == .comment)
        #expect(k["30"] == .number)
    }

    @Test func javascriptTemplateStrings() {
        let k = kinds("const msg = `hi ${name}`", "js")
        #expect(k["const"] == .keyword)
        #expect(k["`hi ${name}`"] == .string)
    }
}
