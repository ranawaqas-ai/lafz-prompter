import AVFoundation
import Dependencies

/// Microphone permission.
struct MicPermissionClient: Sendable {
    var status: @Sendable () -> AVAuthorizationStatus
    /// Asks when the user has not decided yet; returns whether access is on.
    var request: @Sendable () async -> Bool
}

extension MicPermissionClient: DependencyKey {
    static let liveValue = MicPermissionClient(
        status: { AVCaptureDevice.authorizationStatus(for: .audio) },
        request: { await AVCaptureDevice.requestAccess(for: .audio) })
}

extension DependencyValues {
    var micPermission: MicPermissionClient {
        get { self[MicPermissionClient.self] }
        set { self[MicPermissionClient.self] = newValue }
    }
}
