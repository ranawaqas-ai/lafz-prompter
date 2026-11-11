import Dependencies

/// Where a Call Assist session hears both sides of the call: the mic,
/// system audio and on-device transcription in the app.
struct UtteranceSourceClient: Sendable {
    var make: @Sendable () -> UtteranceSource
}

extension UtteranceSourceClient: DependencyKey {
    static let liveValue = UtteranceSourceClient(make: { CallListener() })
}

extension DependencyValues {
    var utteranceSource: UtteranceSourceClient {
        get { self[UtteranceSourceClient.self] }
        set { self[UtteranceSourceClient.self] = newValue }
    }
}
