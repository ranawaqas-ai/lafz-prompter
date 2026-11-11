import Foundation
import os

/// Token usage per answer, to confirm the knowledge base is read from cache.
let providerLog = Logger(subsystem: "space.waqasrana.LafzPrompter", category: "CallAssistProvider")

enum AssistProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openAI

    var id: Self { self }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        }
    }

    /// Current models, fastest first. The first is the default: the answer has
    /// to start within a couple of seconds.
    var models: [AssistModel] {
        switch self {
        case .anthropic:
            return [
                AssistModel(id: "claude-haiku-5-5", name: "Claude Haiku 5.5 (fastest)", contextWindow: 1_000_000),
                AssistModel(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", contextWindow: 1_000_000),
                AssistModel(id: "claude-opus-5-5", name: "Claude Opus 5.5", contextWindow: 1_000_000),
                AssistModel(id: "claude-fable-5-2", name: "Claude Fable 5.2 (most capable, slowest)", contextWindow: 1_000_000),
            ]
        case .openAI:
            return [
                AssistModel(id: "gpt-6-luna", name: "GPT-6 Luna (fastest)", contextWindow: 1_050_000),
                AssistModel(id: "gpt-6.1-terra", name: "GPT-6.1 Terra", contextWindow: 1_050_000),
                AssistModel(id: "gpt-6.1-sol", name: "GPT-6.1 Sol", contextWindow: 1_050_000),
                AssistModel(id: "gpt-6-astra", name: "GPT-6 Astra (most capable, slowest)", contextWindow: 1_050_000),
            ]
        }
    }

    var defaultModel: AssistModel { models[0] }

    func model(withID id: String?) -> AssistModel {
        models.first { $0.id == id } ?? defaultModel
    }

    func makeClient(apiKey: String, model: String) -> AnswerProvider {
        switch self {
        case .anthropic: return AnthropicProvider(apiKey: apiKey, model: model)
        case .openAI: return OpenAIProvider(apiKey: apiKey, model: model)
        }
    }
}

struct AssistModel: Hashable, Identifiable {
    let id: String
    let name: String
    /// Tokens of input the model accepts; the knowledge base must fit in it.
    let contextWindow: Int
}

/// Everything one answer is built from. The knowledge base comes before the
/// per-question parts so the providers can cache it as a stable prefix.
struct AnswerRequest {
    var instructions: String
    var knowledge: String
    var transcript: String
    var question: String
    /// A JPEG of the user's screen at the time of the question, if enabled.
    var screenshot: Data? = nil

    var userMessage: String {
        var parts: [String] = []
        if !transcript.isEmpty {
            parts.append("Conversation so far:\n\(transcript)")
        }
        if screenshot != nil {
            parts.append("A screenshot of my screen right now is attached; use it if the question refers to what is on screen.")
        }
        parts.append("Answer this now:\n\(question)")
        return parts.joined(separator: "\n\n")
    }
}

protocol AnswerProvider {
    /// Streams the answer as text fragments, in order.
    func stream(_ request: AnswerRequest) -> AsyncThrowingStream<String, Error>
}

struct ProviderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Shared transport for both providers: POST a JSON body, read the response as
/// server-sent events, and turn each `data:` payload into text with `parse`.
enum StreamingRequest {
    static func run(
        _ request: URLRequest,
        parse: @escaping @Sendable (Data) throws -> String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw ProviderError(message: errorMessage(from: body) ?? "HTTP \(status)")
                    }
                    for try await line in bytes.lines {
                        guard let payload = ServerSentEvents.data(fromLine: line) else { continue }
                        if let text = try parse(Data(payload.utf8)) {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Both APIs return `{"error": {"message": ...}}` on a failed request.
    static func errorMessage(from body: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        return error?["message"] as? String
    }
}

enum ServerSentEvents {
    /// The payload of a `data:` line, or nil for event names, comments, blank
    /// lines and OpenAI's `[DONE]` terminator.
    static func data(fromLine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        return payload
    }
}
