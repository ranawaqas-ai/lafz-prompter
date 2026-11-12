import AVFoundation

/// What Call Assist still needs before it can run: a key for the selected
/// provider, the microphone, and system audio (the other side of the call).
/// Screen recording is optional; only screenshots need it.
struct AssistReadiness: Equatable {
    var hasKey: Bool
    var microphone: AVAuthorizationStatus
    /// macOS cannot be asked about system audio ahead of time, so this is
    /// done once Call Assist has heard the other side.
    var heardSystemAudio: Bool
    var screenRecording: Bool

    var requiredDone: Int {
        [hasKey, microphone == .authorized, heardSystemAudio].filter { $0 }.count
    }
    static let requiredCount = 3
    var isComplete: Bool { requiredDone == Self.requiredCount }
}
