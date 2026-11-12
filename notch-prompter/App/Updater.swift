import Foundation
import Observation
import Sparkle

/// Checks the appcast on the website for new versions (Sparkle). The feed URL
/// and signing key live in Info.plist, so a `swift run` build, which has no
/// bundle Info.plist, never starts the updater.
@MainActor
@Observable
final class Updater {
    private let controller: SPUStandardUpdaterController?
    private(set) var canCheckForUpdates = false
    private var observation: NSKeyValueObservation?

    init(bundle: Bundle = .main) {
        guard bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            MainActor.assumeIsolated { self?.canCheckForUpdates = canCheck }
        }
    }

    var isAvailable: Bool { controller != nil }

    /// Sparkle stores this in the app's defaults, so it outlives a relaunch.
    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
