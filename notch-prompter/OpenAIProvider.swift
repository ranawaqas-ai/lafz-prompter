import Foundation

/// OpenAI Responses API over raw HTTP.
struct OpenAIProvider: AnswerProvider {
    let apiKey: String
    let model: String

    func stream(_ request: AnswerRequest) -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body(for: request))
        return StreamingRequest.run(urlRequest, parse: Self.text(fromEvent:))
    }

    func body(for request: AnswerRequest) -> [String: Any] {
        // OpenAI caches identical prompt prefixes automatically, so the
        // instructions and knowledge base go first and never change mid-call.
        var instructions = request.instructions
        if !request.knowledge.isEmpty {
            instructions += "\n\n<knowledge_base>\n\(request.knowledge)\n</knowledge_base>"
        }
        return [
            "model": model,
            "stream": true,
            "max_output_tokens": 1024,
            "instructions": instructions,
            "input": request.userMessage,
        ]
    }

    /// Text from a `response.output_text.delta` event; throws on failure events.
    static func text(fromEvent data: Data) throws -> String? {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch event["type"] as? String {
        case "response.output_text.delta":
            return event["delta"] as? String
        case "error":
            throw ProviderError(message: event["message"] as? String ?? "OpenAI stream error")
        case "response.failed":
            let response = event["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            throw ProviderError(message: error?["message"] as? String ?? "OpenAI response failed")
        default:
            return nil
        }
    }
}
