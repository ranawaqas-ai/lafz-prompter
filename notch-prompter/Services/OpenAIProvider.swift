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
            "max_output_tokens": 4096,
            "instructions": instructions,
            "input": Self.input(for: request),
        ]
    }

    /// The question as text, with the screenshot as an image part when there is one.
    static func input(for request: AnswerRequest) -> Any {
        guard let screenshot = request.screenshot else { return request.userMessage }
        return [[
            "role": "user",
            "content": [
                ["type": "input_image", "image_url": "data:image/jpeg;base64,\(screenshot.base64EncodedString())"],
                ["type": "input_text", "text": request.userMessage],
            ],
        ]]
    }

    /// Text from a `response.output_text.delta` event; throws on failure events.
    static func text(fromEvent data: Data) throws -> String? {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch event["type"] as? String {
        case "response.output_text.delta":
            return event["delta"] as? String
        case "response.completed":
            let usage = (event["response"] as? [String: Any])?["usage"] as? [String: Any]
            let details = usage?["input_tokens_details"] as? [String: Any]
            let cached = details?["cached_tokens"] as? Int ?? 0
            let input = usage?["input_tokens"] as? Int ?? 0
            providerLog.info("OpenAI input tokens: \(input), \(cached) read from cache")
            return nil
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
