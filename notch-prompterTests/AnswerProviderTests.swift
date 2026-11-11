import Foundation
import Testing
@testable import LafzPrompter

struct ServerSentEventsTests {
    @Test(arguments: [
        ("data: {\"a\":1}", "{\"a\":1}"),
        ("data:{\"a\":1}", "{\"a\":1}"),
    ])
    func dataLinesYieldTheirPayload(line: String, payload: String) {
        #expect(ServerSentEvents.data(fromLine: line) == payload)
    }

    @Test(arguments: ["event: content_block_delta", "", ": ping", "data: [DONE]", "data: "])
    func otherLinesYieldNothing(line: String) {
        #expect(ServerSentEvents.data(fromLine: line) == nil)
    }
}

struct AnthropicProviderTests {
    private func parse(_ json: String) throws -> String? {
        try AnthropicProvider.text(fromEvent: Data(json.utf8))
    }

    @Test func textDeltaYieldsText() throws {
        let event = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        #expect(try parse(event) == "Hello")
    }

    @Test func nonTextEventsYieldNothing() throws {
        #expect(try parse(#"{"type":"message_start","message":{}}"#) == nil)
        #expect(try parse(#"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"x"}}"#) == nil)
        #expect(try parse(#"{"type":"message_stop"}"#) == nil)
    }

    @Test func errorEventThrowsItsMessage() {
        let event = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        #expect(throws: ProviderError.self) { try parse(event) }
    }

    @Test func refusalStopsTheAnswerWithAMessage() throws {
        let event = #"{"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{}}"#
        #expect(throws: ProviderError.self) { try parse(event) }
        #expect(try parse(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{}}"#) == nil)
    }

    @Test func fallbackIsRequestedOnlyWhereSupported() {
        let request = AnswerRequest(instructions: "i", knowledge: "", transcript: "", question: "q")
        #expect(AnthropicProvider(apiKey: "k", model: "claude-opus-5-5").body(for: request)["fallbacks"] as? String == "default")
        #expect(AnthropicProvider(apiKey: "k", model: "claude-haiku-5-5").body(for: request)["fallbacks"] == nil)
    }

    @Test func everyListedModelHasAContextWindow() {
        for provider in AssistProvider.allCases {
            #expect(!provider.models.isEmpty)
            #expect(provider.models.allSatisfy { $0.contextWindow > 0 })
            #expect(provider.model(withID: "no-such-model") == provider.defaultModel)
        }
    }

    @Test func knowledgeBaseIsCachedAndOmittedWhenEmpty() {
        let provider = AnthropicProvider(apiKey: "k", model: "m")
        let withKnowledge = provider.body(for: AnswerRequest(instructions: "i", knowledge: "kb", transcript: "", question: "q"))
        let system = withKnowledge["system"] as? [[String: Any]]
        #expect(system?.count == 2)
        #expect(system?.last?["cache_control"] != nil)

        let without = provider.body(for: AnswerRequest(instructions: "i", knowledge: "", transcript: "", question: "q"))
        #expect((without["system"] as? [[String: Any]])?.count == 1)
    }
}

struct OpenAIProviderTests {
    private func parse(_ json: String) throws -> String? {
        try OpenAIProvider.text(fromEvent: Data(json.utf8))
    }

    @Test func outputTextDeltaYieldsText() throws {
        #expect(try parse(#"{"type":"response.output_text.delta","item_id":"x","output_index":0,"content_index":0,"delta":"Hi"}"#) == "Hi")
    }

    @Test func otherEventsYieldNothing() throws {
        #expect(try parse(#"{"type":"response.created","response":{}}"#) == nil)
        #expect(try parse(#"{"type":"response.completed","response":{}}"#) == nil)
    }

    @Test func failureEventsThrow() {
        #expect(throws: ProviderError.self) { try parse(#"{"type":"error","message":"bad"}"#) }
        #expect(throws: ProviderError.self) {
            try parse(#"{"type":"response.failed","response":{"error":{"message":"bad"}}}"#)
        }
    }
}

struct AnswerRequestTests {
    @Test func userMessageIncludesTranscriptOnlyWhenPresent() {
        let bare = AnswerRequest(instructions: "", knowledge: "", transcript: "", question: "Why?")
        #expect(bare.userMessage == "Answer this now:\nWhy?")
        let withTranscript = AnswerRequest(instructions: "", knowledge: "", transcript: "them: hi", question: "Why?")
        #expect(withTranscript.userMessage.hasPrefix("Conversation so far:\nthem: hi"))
    }
}

struct ScreenshotRequestTests {
    private let request = AnswerRequest(instructions: "i", knowledge: "", transcript: "", question: "q",
                                        screenshot: Data([0xFF, 0xD8]))

    @Test func anthropicSendsTheImageBeforeTheText() {
        let blocks = AnthropicProvider.userContent(for: request) as? [[String: Any]]
        #expect(blocks?.map { $0["type"] as? String } == ["image", "text"])
        let source = blocks?.first?["source"] as? [String: Any]
        #expect(source?["data"] as? String == Data([0xFF, 0xD8]).base64EncodedString())
    }

    @Test func openAISendsTheImageAsADataURL() {
        let input = OpenAIProvider.input(for: request) as? [[String: Any]]
        let parts = input?.first?["content"] as? [[String: Any]]
        #expect((parts?.first?["image_url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @Test func withoutAScreenshotTheQuestionStaysPlainText() {
        let plain = AnswerRequest(instructions: "i", knowledge: "", transcript: "", question: "q")
        #expect(AnthropicProvider.userContent(for: plain) as? String == plain.userMessage)
        #expect(OpenAIProvider.input(for: plain) as? String == plain.userMessage)
        #expect(!plain.userMessage.contains("screenshot"))
    }
}
