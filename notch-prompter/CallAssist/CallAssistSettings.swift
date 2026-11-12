import Foundation
import Dependencies
import Observation

/// User settings for Call Assist.
@MainActor @Observable
final class CallAssistSettings {
    static let defaultInstructions = """
    You are helping me answer questions on a live call. I will read your answer aloud. \
    Answer in 2 to 4 short sentences, first person, plain spoken English. \
    Use the knowledge base when it is relevant; if it does not cover the question, \
    say so in a few words rather than invent facts.
    """

    var provider: AssistProvider {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }
    var instructions: String {
        didSet { defaults.set(instructions, forKey: Keys.instructions) }
    }
    /// Keep every question and answer in a SQLite file on this Mac.
    var saveHistory: Bool {
        didSet { defaults.set(saveHistory, forKey: Keys.saveHistory) }
    }
    /// Attach a screenshot of the front display to each answer.
    var includeScreen: Bool {
        didSet { defaults.set(includeScreen, forKey: Keys.includeScreen) }
    }
    /// Call Assist has heard the other side of a call at least once, so the
    /// system-audio permission is known to work.
    var heardSystemAudio: Bool {
        didSet { if heardSystemAudio != oldValue { defaults.set(heardSystemAudio, forKey: Keys.heardSystemAudio) } }
    }
    /// Providers that have a key in the Keychain. Mirrors the Keychain so views
    /// can react without reading it on every render.
    private(set) var providersWithKey: Set<AssistProvider>
    /// Files and folders the answers draw on, read fresh when Assist starts.
    private(set) var knowledgeSources: [URL] {
        didSet {
            defaults.set(knowledgeSources.map(\.path), forKey: Keys.knowledgeSources)
            refreshKnowledgeSummary()
        }
    }
    /// Per-source token estimates for Settings; nil while counting.
    private(set) var knowledgeSummary: [KnowledgeBase.Source]?

    @ObservationIgnored @Dependency(\.settingsStorage) private var defaults
    @ObservationIgnored @Dependency(\.keychain) private var keychain
    @ObservationIgnored @Dependency(\.answerClient) private var answerClient
    @ObservationIgnored private var summaryTask: Task<Void, Never>?

    private enum Keys {
        static let provider = "AssistProvider"
        static let instructions = "AssistInstructions"
        static let includeScreen = "AssistIncludeScreen"
        static let saveHistory = "AssistSaveHistory"
        static let knowledgeSources = "AssistKnowledgeSources"
        static let heardSystemAudio = "AssistHeardSystemAudio"
        static func model(_ p: AssistProvider) -> String { "AssistModel.\(p.rawValue)" }
    }

    init() {
        // Read through locals: the stored properties are not all set yet.
        @Dependency(\.settingsStorage) var defaults
        @Dependency(\.keychain) var keychain
        provider = AssistProvider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .anthropic
        instructions = defaults.string(forKey: Keys.instructions) ?? Self.defaultInstructions
        includeScreen = defaults.object(forKey: Keys.includeScreen) as? Bool ?? true
        saveHistory = defaults.object(forKey: Keys.saveHistory) as? Bool ?? true
        heardSystemAudio = defaults.bool(forKey: Keys.heardSystemAudio)
        providersWithKey = Set(AssistProvider.allCases.filter(keychain.hasKey))
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

    /// The selected model for the current provider. Only models from the
    /// provider's list can be chosen, so a stored name that is no longer
    /// listed falls back to the default.
    var model: AssistModel {
        // Stored in defaults per provider, so Observation is told by hand.
        get {
            access(keyPath: \.model)
            return provider.model(withID: defaults.string(forKey: Keys.model(provider)))
        }
        set {
            withMutation(keyPath: \.model) { defaults.set(newValue.id, forKey: Keys.model(provider)) }
        }
    }

    var contextWindow: Int { model.contextWindow }

    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try keychain.save(trimmed, provider)
        providersWithKey.insert(provider)
    }

    func removeKey() {
        keychain.delete(provider)
        providersWithKey.remove(provider)
    }

    /// A client for the selected provider, or nil when no key is saved.
    func makeClient() -> AnswerProvider? {
        guard let key = keychain.key(provider) else { return nil }
        return answerClient.make(provider, key, model.id)
    }
}
