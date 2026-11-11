import Dependencies

/// Screenshots of the display the user is working on, for answers that need
/// to see the screen.
@MainActor
protocol ScreenCapture: AnyObject {
    var latest: ScreenSnapshotter.Snapshot? { get }
    var problem: String? { get }
    func start()
    func stop()
    func refresh() async
}

extension ScreenSnapshotter: ScreenCapture {}

struct ScreenCaptureClient: Sendable {
    var make: @MainActor @Sendable () -> any ScreenCapture
}

extension ScreenCaptureClient: DependencyKey {
    static let liveValue = ScreenCaptureClient(make: { ScreenSnapshotter() })
}

extension DependencyValues {
    var screenCapture: ScreenCaptureClient {
        get { self[ScreenCaptureClient.self] }
        set { self[ScreenCaptureClient.self] = newValue }
    }
}
