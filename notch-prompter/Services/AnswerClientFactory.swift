import Dependencies

/// Makes the AI client that streams answers. The network calls stay inside
/// AnthropicProvider and OpenAIProvider.
struct AnswerClientFactory: Sendable {
    var make: @Sendable (_ provider: AssistProvider, _ apiKey: String, _ model: String) -> AnswerProvider
}

extension AnswerClientFactory: DependencyKey {
    static let liveValue = AnswerClientFactory(make: { provider, apiKey, model in
        provider.makeClient(apiKey: apiKey, model: model)
    })
}

extension DependencyValues {
    var answerClient: AnswerClientFactory {
        get { self[AnswerClientFactory.self] }
        set { self[AnswerClientFactory.self] = newValue }
    }
}
