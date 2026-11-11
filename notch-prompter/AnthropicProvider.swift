import Foundation

/// Claude Messages API over raw HTTP (there is no official Swift SDK).
struct AnthropicProvider: AnswerProvider {
    let apiKey: String
    let model: String

    func stream(_ request: AnswerRequest) -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body(for: request))
        return StreamingRequest.run(urlRequest, parse: Self.text(fromEvent:))
    }

    func body(for request: AnswerRequest) -> [String: Any] {
        var system: [[String: Any]] = [["type": "text", "text": request.instructions]]
        if !request.knowledge.isEmpty {
            // The breakpoint sits after the knowledge base, so every question
            // in a call reuses the cached instructions and files. One hour,
            // because questions on a call can be more than the default five
            // minutes apart.
            system.append([
                "type": "text",
                "text": "<knowledge_base>\n\(request.knowledge)\n</knowledge_base>",
                "cache_control": ["type": "ephemeral", "ttl": "1h"],
            ])
        }
        return [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            // Low effort keeps thinking short: the user is waiting mid-call.
            "output_config": ["effort": "low"],
            "system": system,
            "messages": [["role": "user", "content": request.userMessage]],
        ]
    }

    /// Text from a `content_block_delta` event; throws on an `error` event.
    static func text(fromEvent data: Data) throws -> String? {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch event["type"] as? String {
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any]
            guard delta?["type"] as? String == "text_delta" else { return nil }
            return delta?["text"] as? String
        case "error":
            let error = event["error"] as? [String: Any]
            throw ProviderError(message: error?["message"] as? String ?? "Anthropic stream error")
        default:
            return nil
        }
    }
}
