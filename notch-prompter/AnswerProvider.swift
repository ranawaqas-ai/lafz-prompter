import Foundation

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

    /// Fast, cheap defaults: the answer has to start within a couple of seconds.
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-haiku-5-5"
        case .openAI: return "gpt-6-luna"
        }
    }

    /// Context windows of the default models, in tokens. Other model names use
    /// the number the user enters in Settings.
    var defaultContextWindow: Int {
        switch self {
        case .anthropic: return 1_000_000
        case .openAI: return 1_050_000
        }
    }

    func makeClient(apiKey: String, model: String) -> AnswerProvider {
        switch self {
        case .anthropic: return AnthropicProvider(apiKey: apiKey, model: model)
        case .openAI: return OpenAIProvider(apiKey: apiKey, model: model)
        }
    }
}

/// Everything one answer is built from. The knowledge base comes before the
/// per-question parts so the providers can cache it as a stable prefix.
struct AnswerRequest {
    var instructions: String
    var knowledge: String
    var transcript: String
    var question: String

    var userMessage: String {
        var parts: [String] = []
        if !transcript.isEmpty {
            parts.append("Conversation so far:\n\(transcript)")
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
