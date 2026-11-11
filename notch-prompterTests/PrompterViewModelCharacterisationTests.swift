import AppKit
import Dependencies
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import LafzPrompter

/// Characterisation tests: they record what PrompterViewModel does today,
/// odd parts included, so a refactor that changes behaviour fails here. A
/// test named "currently..." pins behaviour that may be a bug; change it in
/// its own commit, on purpose, and update the test with it.
@MainActor
@Suite(.serialized)
struct PrompterViewModelCharacterisationTests {
    /// A throwaway defaults suite, so tests never touch the real settings.
    private final class Suite {
        let name = "lafz-tests-\(UUID().uuidString)"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { defaults.removePersistentDomain(forName: name) }

        var stored: [String: Any] { defaults.persistentDomain(forName: name) ?? [:] }
    }

    /// A view model on a throwaway defaults suite, with no display link
    /// (tests call `tick` with their own times) and no real global shortcuts.
    private func makeViewModel(_ suite: Suite) -> PrompterViewModel {
        withDependencies {
            $0.settingsStorage = suite.defaults
            $0.frameClock = .stopped
            $0.globalShortcuts = GlobalShortcuts(registersWithSystem: false)
        } operation: {
            PrompterViewModel()
        }
    }

    /// Lets debounced Combine work on the main run loop happen.
    private func runMainLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: Playback

    @Test func playMovesBySpeedTimesElapsedTimeFromTheSecondTick() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.speed = 12
        vm.play()
        vm.tick(current: 100)       // first tick only records the time
        #expect(vm.offset == 0)
        vm.tick(current: 101.5)
        #expect(vm.offset == 18)
    }

    @Test func pausedTicksDoNotMoveAndPlayAgainDoesNotJump() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.speed = 10
        vm.play()
        vm.tick(current: 0)
        vm.tick(current: 1)
        vm.pause()
        vm.tick(current: 5)
        #expect(vm.offset == 10)
        vm.play()
        vm.tick(current: 9)         // a fresh first tick after play
        vm.tick(current: 10)
        #expect(vm.offset == 20)
    }

    @Test func resetStopsAndGoesBackToTheTop() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.play()
        vm.offset = 300
        vm.reset()
        #expect(vm.offset == 0)
        #expect(!vm.isPlaying)
    }

    @Test func togglePlaybackWithoutVoiceFlipsPlaying() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.togglePlayback()
        #expect(vm.isPlaying)
        vm.togglePlayback()
        #expect(!vm.isPlaying)
        vm.play()
        vm.finishScript()
        #expect(!vm.isPlaying)
    }

    // MARK: Manual scrolling and speed

    @Test func scrollingUpStopsAtTheTop() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.offset = 30
        vm.scrollUp()               // manualScrollAmount defaults to 50
        #expect(vm.offset == 0)
        vm.offset = 30
        vm.scrollBack()             // backScrollAmount is 20
        #expect(vm.offset == 10)
    }

    @Test func currentlyScrollingDownHasNoLowerLimit() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.text = "Short."
        for _ in 0..<100 { vm.scrollDown() }
        #expect(vm.offset == 5000)
    }

    @Test func speedStepsByTheIncrementWithinOneToForty() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.speed = 39
        vm.increaseSpeed()
        #expect(vm.speed == 40)
        vm.speed = 2
        vm.decreaseSpeed()
        #expect(vm.speed == 1)
        vm.speed = 10
        vm.increaseSpeed()
        #expect(vm.speed == 12)
    }

    @Test func scrollRedirectTakesOverEveryScrollControl() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        var moves: [CGFloat] = []
        vm.scrollRedirect = { moves.append($0) }
        vm.offset = 100
        vm.scrollUp()
        vm.scrollDown()
        vm.scrollBack()
        #expect(moves == [-50, 50, -20])
        #expect(vm.offset == 100)
    }

    // MARK: Saving (approval)

    /// Every setting a fresh install writes, as an approved text file.
    @Test func approvedDefaultSettings() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.saveSettings()
        assertSnapshot(of: Self.describe(suite.stored), as: .lines, named: "defaults")
    }

    /// How stored values are read back, including the fallbacks for zero,
    /// missing and unknown values.
    @Test func approvedLoadingOfStoredValues() {
        let cases: [(String, [String: Any])] = [
            ("nothing stored", [:]),
            ("zeros", ["PrompterSpeed": 0.0, "PrompterFontSize": 0.0, "PrompterWidth": 0.0,
                       "PrompterHeight": 0.0, "AudioThreshold": 0.0, "SpeedIncrement": 0.0]),
            ("unknown names", ["FontDesign": "gothic", "PrompterTheme": "sepia",
                               "HorizontalAlignment": "middle", "TextAlignment": "justified"]),
            ("custom values", ["PrompterSpeed": 20.0, "PrompterFontSize": 18.0, "PrompterTheme": "light",
                               "HideFromScreenRecording": true, "FontChoice": "custom:Noto Nastaliq Urdu",
                               "PrompterBackgroundOpacity": 0.6]),
        ]
        var report = ""
        for (name, values) in cases {
            let suite = Suite()
            for (key, value) in values { suite.defaults.set(value, forKey: key) }
            let vm = makeViewModel(suite)
            report += "== \(name)\n" + Self.describe(vm) + "\n"
        }
        assertSnapshot(of: report, as: .lines, named: "loading")
    }

    @Test func savedSettingsRoundTrip() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.speed = 22
        vm.fontSize = 17
        vm.prompterTheme = .light
        vm.textAlignment = .leading
        vm.text = "Round trip [pause]"
        vm.saveSettings()
        #expect(Self.describe(makeViewModel(suite)) == Self.describe(vm))
    }

    @Test func currentlyPlayAndPauseRewriteEverySetting() {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.saveSettings()
        suite.defaults.removeObject(forKey: "PrompterText")
        vm.play()
        runMainLoop(for: 0.5)       // the save is debounced by 300 ms
        #expect(suite.stored["PrompterText"] as? String == vm.text)
    }

    // MARK: Rendering (approval images)

    @Test(arguments: [PrompterTheme.dark, .light])
    func approvedPrompterImage(theme: PrompterTheme) {
        let suite = Suite()
        let vm = makeViewModel(suite)
        vm.text = "Good morning everyone. [smile]\nToday I want to share three points."
        vm.prompterTheme = theme
        vm.fontSize = 14
        vm.showProgressBar = false
        let view = NSHostingView(rootView: PrompterView(viewModel: vm).frame(width: 320, height: 160))
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        view.appearance = NSAppearance(named: .aqua)
        assertSnapshot(of: view, as: .image(precision: 0.98), named: theme.rawValue)
    }

    // MARK: Rendering the state as text

    static func describe(_ stored: [String: Any]) -> String {
        stored.keys.sorted().map { key in
            let value = stored[key]!
            if let text = value as? String, text.count > 60 {
                return "\(key) = \(text.count) characters, starting \"\(text.prefix(40))\""
            }
            return "\(key) = \(value)"
        }.joined(separator: "\n")
    }

    static func describe(_ vm: PrompterViewModel) -> String {
        let values: [(String, Any)] = [
            ("speed", vm.speed), ("fontSize", vm.fontSize), ("lineHeight", vm.lineHeight),
            ("pauseOnHover", vm.pauseOnHover), ("prompterWidth", vm.prompterWidth),
            ("prompterHeight", vm.prompterHeight), ("voiceActivation", vm.voiceActivation),
            ("audioThreshold", vm.audioThreshold), ("fontDesign", vm.fontDesign.rawValue),
            ("fontChoice", vm.fontChoice.storageValue ?? "nil"), ("selectedScreenIndex", vm.selectedScreenIndex),
            ("enableTopFade", vm.enableTopFade), ("enableBottomFade", vm.enableBottomFade),
            ("topFadeHeight", vm.topFadeHeight), ("bottomFadeHeight", vm.bottomFadeHeight),
            ("showHoverControls", vm.showHoverControls), ("hideFromScreenRecording", vm.hideFromScreenRecording),
            ("prompterTheme", vm.prompterTheme.rawValue), ("backgroundOpacity", vm.backgroundOpacity),
            ("horizontalAlignment", vm.horizontalAlignment.rawValue), ("textAlignment", vm.textAlignment.rawValue),
            ("showProgressBar", vm.showProgressBar), ("enableGlobalKeyboardShortcuts", vm.enableGlobalKeyboardShortcuts),
            ("speedIncrement", vm.speedIncrement), ("manualScrollAmount", vm.manualScrollAmount),
            ("textLength", vm.text.count),
        ]
        return values.map { "\($0.0) = \($0.1)" }.joined(separator: "\n")
    }
}
