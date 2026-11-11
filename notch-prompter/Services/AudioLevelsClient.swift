import Dependencies

/// The mic level that drives voice-activated scrolling.
struct AudioLevelsClient: Sendable {
    var makeMonitor: @Sendable () -> AudioMonitor
}

extension AudioLevelsClient: DependencyKey {
    static let liveValue = AudioLevelsClient(makeMonitor: { AudioMonitor() })
}

extension DependencyValues {
    var audioLevels: AudioLevelsClient {
        get { self[AudioLevelsClient.self] }
        set { self[AudioLevelsClient.self] = newValue }
    }
}
