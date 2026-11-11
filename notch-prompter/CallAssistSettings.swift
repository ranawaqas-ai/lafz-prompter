import Foundation
import Combine

/// User settings for Call Assist. Kept apart from PrompterViewModel so typing in
/// the Assist tab does not re-render the prompter.
final class CallAssistSettings: ObservableObject {
    static let defaultInstructions = """
    You are helping me answer questions on a live call. I will read your answer aloud. \
    Answer in 2 to 4 short sentences, first person, plain spoken English. \
    Use the knowledge base when it is relevant; if it does not cover the question, \
    say so in a few words rather than invent facts.
    """

    @Published var provider: AssistProvider {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }
    @Published var instructions: String {
        didSet { defaults.set(instructions, forKey: Keys.instructions) }
    }
    /// Providers that have a key in the Keychain. Mirrors the Keychain so views
    /// can react without reading it on every render.
    @Published private(set) var providersWithKey: Set<AssistProvider>
    /// Files and folders the answers draw on, read fresh when Assist starts.
    @Published private(set) var knowledgeSources: [URL] {
        didSet {
            defaults.set(knowledgeSources.map(\.path), forKey: Keys.knowledgeSources)
            refreshKnowledgeSummary()
        }
    }
    /// Per-source token estimates for Settings; nil while counting.
    @Published private(set) var knowledgeSummary: [KnowledgeBase.Source]?

    private let defaults: UserDefaults
    private var summaryTask: Task<Void, Never>?

    private enum Keys {
        static let provider = "AssistProvider"
        static let instructions = "AssistInstructions"
        static let knowledgeSources = "AssistKnowledgeSources"
        static func model(_ p: AssistProvider) -> String { "AssistModel.\(p.rawValue)" }
        static func contextWindow(_ p: AssistProvider) -> String { "AssistContextWindow.\(p.rawValue)" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = AssistProvider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .anthropic
        instructions = defaults.string(forKey: Keys.instructions) ?? Self.defaultInstructions
        providersWithKey = Set(AssistProvider.allCases.filter(KeychainStore.hasKey))
        knowledgeSources = (defaults.stringArray(forKey: Keys.knowledgeSources) ?? []).map {
            URL(fileURLWithPath: $0)
        }
        refreshKnowledgeSummary()
    }

    func addKnowledgeSources(_ urls: [URL]) {
        knowledgeSources += urls.filter { !knowledgeSources.contains($0) }
    }

    func removeKnowledgeSource(_ url: URL) {
        knowledgeSources.removeAll { $0 == url }
    }

    var knowledgeTokens: Int? { knowledgeSummary?.reduce(0) { $0 + $1.tokens } }

    /// Why Assist cannot start with the current knowledge base, or nil.
    var knowledgeOverflowMessage: String? {
        guard let tokens = knowledgeTokens, tokens > contextWindow else { return nil }
        return "The knowledge base is about \((tokens - contextWindow).formatted()) tokens over the \(contextWindow.formatted())-token context window. Remove sources or pick a model with a larger window."
    }

    private func refreshKnowledgeSummary() {
        summaryTask?.cancel()
        knowledgeSummary = nil
        let urls = knowledgeSources
        summaryTask = Task { @MainActor [weak self] in
            let sources = await Task.detached(priority: .utility) { KnowledgeBase.load(urls).sources }.value
            guard !Task.isCancelled else { return }
            self?.knowledgeSummary = sources
        }
    }

    /// Call Assist is usable only once a key is saved for the selected provider.
    var isAvailable: Bool { providersWithKey.contains(provider) }

    var model: String {
        get { defaults.string(forKey: Keys.model(provider)) ?? provider.defaultModel }
        set {
            objectWillChange.send()
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            defaults.set(trimmed.isEmpty ? nil : trimmed, forKey: Keys.model(provider))
        }
    }

    var contextWindow: Int {
        get {
            let stored = defaults.integer(forKey: Keys.contextWindow(provider))
            return stored > 0 ? stored : provider.defaultContextWindow
        }
        set {
            objectWillChange.send()
            defaults.set(newValue > 0 ? newValue : nil, forKey: Keys.contextWindow(provider))
        }
    }

    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try KeychainStore.save(trimmed, for: provider)
        providersWithKey.insert(provider)
    }

    func removeKey() {
        KeychainStore.delete(for: provider)
        providersWithKey.remove(provider)
    }

    /// A client for the selected provider, or nil when no key is saved.
    func makeClient() -> AnswerProvider? {
        guard let key = KeychainStore.key(for: provider) else { return nil }
        return provider.makeClient(apiKey: key, model: model)
    }
}
