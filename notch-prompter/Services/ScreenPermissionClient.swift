import CoreGraphics
import Dependencies

/// Whether the app may record the screen, which Call Assist needs only for
/// screenshots.
struct ScreenPermissionClient: Sendable {
    var isAllowed: @Sendable () -> Bool
    /// Shows the system prompt the first time; later it only opens nothing.
    var request: @Sendable () -> Void
}

extension ScreenPermissionClient: DependencyKey {
    static let liveValue = ScreenPermissionClient(
        isAllowed: { CGPreflightScreenCaptureAccess() },
        request: { _ = CGRequestScreenCaptureAccess() })
}

extension DependencyValues {
    var screenPermission: ScreenPermissionClient {
        get { self[ScreenPermissionClient.self] }
        set { self[ScreenPermissionClient.self] = newValue }
    }
}
