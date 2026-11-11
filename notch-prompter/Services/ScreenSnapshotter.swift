import AppKit
import ScreenCaptureKit

/// Keeps the newest screenshot of the display the user is working on, so an
/// answer can see what is on screen. Frames stay in memory and are replaced
/// every interval; nothing is written to disk or sent from here.
@MainActor
final class ScreenSnapshotter {
    struct Snapshot {
        let jpeg: Data
        let capturedAt: Date
    }

    private(set) var latest: Snapshot?
    /// Why capture is not working, e.g. a missing Screen Recording permission.
    private(set) var problem: String?

    private var task: Task<Void, Never>?
    private let interval: Duration = .seconds(2)
    /// Claude and GPT both downscale larger images; sending more only costs time.
    private static let maxLongEdge = 1568

    func start() {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.capture()
                try? await Task.sleep(for: self?.interval ?? .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        latest = nil
        problem = nil
    }

    /// Takes a frame now, for an answer that cannot wait for the next tick.
    func refresh() async {
        await capture()
    }

    private func capture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = frontDisplay(in: content) else { return }
            let scale = min(1, Double(Self.maxLongEdge) / Double(max(display.width, display.height)))
            let config = SCStreamConfiguration()
            config.width = Int(Double(display.width) * scale)
            config.height = Int(Double(display.height) * scale)
            config.showsCursor = false
            let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let jpeg = NSBitmapImageRep(cgImage: image)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }
            latest = Snapshot(jpeg: jpeg, capturedAt: Date())
            problem = nil
        } catch {
            problem = "Screen capture is off. Allow Lafz Prompter in System Settings > Privacy & Security > Screen & System Audio Recording."
        }
    }

    /// The display holding the frontmost app's largest window, else the main one.
    private func frontDisplay(in content: SCShareableContent) -> SCDisplay? {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontWindow = content.windows
            .filter { $0.owningApplication?.processID == frontPID && $0.windowLayer == 0 && $0.isOnScreen }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        if let frontWindow {
            let centre = CGPoint(x: frontWindow.frame.midX, y: frontWindow.frame.midY)
            if let display = content.displays.first(where: { $0.frame.contains(centre) }) { return display }
        }
        return content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
    }
}
