import Dependencies

/// API keys for Call Assist, one per provider.
struct KeychainClient: Sendable {
    /// Checks for a key without reading it, so no Keychain prompt appears.
    var hasKey: @Sendable (AssistProvider) -> Bool
    var key: @Sendable (AssistProvider) -> String?
    var save: @Sendable (String, AssistProvider) throws -> Void
    var delete: @Sendable (AssistProvider) -> Void
}

extension KeychainClient: DependencyKey {
    static let liveValue = KeychainClient(
        hasKey: { KeychainStore.hasKey(for: $0) },
        key: { KeychainStore.key(for: $0) },
        save: { try KeychainStore.save($0, for: $1) },
        delete: { KeychainStore.delete(for: $0) })
}

extension DependencyValues {
    var keychain: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}
