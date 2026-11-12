import AppKit
import Dependencies
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import LafzPrompter

/// Characterisation tests for the prompter: Playback and Preferences, which
/// replaced PrompterViewModel with the same behaviour. A test named
/// "currently..." pins behaviour that may be a bug; change it in its own
/// commit, on purpose, and update the test with it.
@MainActor
@Suite(.serialized)
struct PrompterCharacterisationTests {
    /// A throwaway defaults suite, so tests never touch the real settings.
    private final class Suite {
        let name = "lafz-tests-\(UUID().uuidString)"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { defaults.removePersistentDomain(forName: name) }

        var stored: [String: Any] { defaults.persistentDomain(forName: name) ?? [:] }
    }

    /// Preferences on a throwaway defaults suite.
    private func makePreferences(_ suite: Suite) -> Preferences {
        withDependencies { $0.settingsStorage = suite.defaults } operation: { Preferences() }
    }

    /// Playback with no display link (tests call `tick` with their own times)
    /// and no real global shortcuts.
    private func makePlayback(_ preferences: Preferences) -> Playback {
        withDependencies {
            $0.frameClock = .stopped
            $0.globalShortcuts = GlobalShortcuts(registersWithSystem: false)
        } operation: {
            Playback(preferences: preferences)
        }
    }

    private func makeModels(_ suite: Suite) -> (Preferences, Playback) {
        let preferences = makePreferences(suite)
        return (preferences, makePlayback(preferences))
    }

    /// Lets work queued on the main actor happen.
    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: Playback

    @Test func playMovesBySpeedTimesElapsedTimeFromTheSecondTick() {
        let suite = Suite()
        let (preferences, playback) = makeModels(suite)
        preferences.speed = 12
        playback.play()
        playback.tick(current: 100)       // first tick only records the time
        #expect(playback.offset == 0)
        playback.tick(current: 101.5)
        #expect(playback.offset == 18)
    }

    @Test func pausedTicksDoNotMoveAndPlayAgainDoesNotJump() {
        let suite = Suite()
        let (preferences, playback) = makeModels(suite)
        preferences.speed = 10
        playback.play()
        playback.tick(current: 0)
        playback.tick(current: 1)
        playback.pause()
        playback.tick(current: 5)
        #expect(playback.offset == 10)
        playback.play()
        playback.tick(current: 9)         // a fresh first tick after play
        playback.tick(current: 10)
        #expect(playback.offset == 20)
    }

    @Test func resetStopsAndGoesBackToTheTop() {
        let suite = Suite()
        let (_, playback) = makeModels(suite)
        playback.play()
        playback.offset = 300
        playback.reset()
        #expect(playback.offset == 0)
        #expect(!playback.isPlaying)
    }

    @Test func togglePlaybackWithoutVoiceFlipsPlaying() {
        let suite = Suite()
        let (_, playback) = makeModels(suite)
        playback.togglePlayback()
        #expect(playback.isPlaying)
        playback.togglePlayback()
        #expect(!playback.isPlaying)
        playback.play()
        playback.finishScript()
        #expect(!playback.isPlaying)
    }

    // MARK: Manual scrolling and speed

    @Test func scrollingUpStopsAtTheTop() {
        let suite = Suite()
        let (_, playback) = makeModels(suite)
        playback.offset = 30
        playback.scrollUp()               // manualScrollAmount defaults to 50
        #expect(playback.offset == 0)
        playback.offset = 30
        playback.scrollBack()             // backScrollAmount is 20
        #expect(playback.offset == 10)
    }

    @Test func currentlyScrollingDownHasNoLowerLimit() {
        let suite = Suite()
        let (_, playback) = makeModels(suite)
        for _ in 0..<100 { playback.scrollDown() }
        #expect(playback.offset == 5000)
    }

    @Test func speedStepsByTheIncrementWithinOneToForty() {
        let suite = Suite()
        let (preferences, playback) = makeModels(suite)
        preferences.speed = 39
        playback.increaseSpeed()
        #expect(preferences.speed == 40)
        preferences.speed = 2
        playback.decreaseSpeed()
        #expect(preferences.speed == 1)
        preferences.speed = 10
        playback.increaseSpeed()
        #expect(preferences.speed == 12)
    }

    @Test func scrollRedirectTakesOverEveryScrollControl() {
        let suite = Suite()
        let (_, playback) = makeModels(suite)
        var moves: [CGFloat] = []
        playback.scrollRedirect = { moves.append($0) }
        playback.offset = 100
        playback.scrollUp()
        playback.scrollDown()
        playback.scrollBack()
        #expect(moves == [-50, 50, -20])
        #expect(playback.offset == 100)
    }

    // MARK: Saving (approval)

    /// Every setting the app writes when it quits on a fresh install, as an
    /// approved text file.
    @Test func approvedDefaultSettings() {
        let suite = Suite()
        let preferences = makePreferences(suite)
        preferences.saveAll()
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
            report += "== \(name)\n" + Self.describe(makePreferences(suite)) + "\n"
        }
        assertSnapshot(of: report, as: .lines, named: "loading")
    }

    @Test func savedSettingsRoundTrip() {
        let suite = Suite()
        let preferences = makePreferences(suite)
        preferences.speed = 22
        preferences.fontSize = 17
        preferences.prompterTheme = .light
        preferences.textAlignment = .leading
        #expect(Self.describe(makePreferences(suite)) == Self.describe(preferences))
    }

    @Test func aChangedSettingWritesOnlyItsOwnKey() {
        let suite = Suite()
        let preferences = makePreferences(suite)
        #expect(suite.stored.isEmpty)
        preferences.speed = 20
        preferences.speed = 20            // the same value again writes nothing new
        #expect(suite.stored.count == 1)
        #expect(suite.stored["PrompterSpeed"] as? Double == 20)
    }

    @Test func playAndPauseWriteNothing() async {
        let suite = Suite()
        let (_, playback) = makeModels(suite)
        playback.play()
        playback.tick(current: 0)
        playback.tick(current: 1)
        playback.pause()
        await wait(0.5)                   // longer than any save debounce
        #expect(suite.stored.isEmpty)
    }

    // MARK: Rendering (approval images)

    @Test(arguments: [PrompterTheme.dark, .light])
    func approvedPrompterImage(theme: PrompterTheme) {
        let suite = Suite()
        let (preferences, playback) = makeModels(suite)
        let files = ScriptLibraryTests.MemoryFiles()
        let library = withDependencies { $0.scriptFiles = files.client } operation: { ScriptLibrary() }
        library.add(text: "Good morning everyone. [smile]\nToday I want to share three points.", title: nil)
        preferences.prompterTheme = theme
        preferences.fontSize = 14
        preferences.showProgressBar = false
        let view = NSHostingView(rootView: PrompterView()
            .environment(preferences)
            .environment(playback)
            .environment(library)
            .frame(width: 320, height: 160))
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

    static func describe(_ preferences: Preferences) -> String {
        let p = preferences
        let values: [(String, Any)] = [
            ("speed", p.speed), ("fontSize", p.fontSize), ("lineHeight", p.lineHeight),
            ("pauseOnHover", p.pauseOnHover), ("prompterWidth", p.prompterWidth),
            ("prompterHeight", p.prompterHeight), ("voiceActivation", p.voiceActivation),
            ("audioThreshold", p.audioThreshold), ("fontDesign", p.fontDesign.rawValue),
            ("fontChoice", p.fontChoice.storageValue ?? "nil"), ("selectedScreenIndex", p.selectedScreenIndex),
            ("enableTopFade", p.enableTopFade), ("enableBottomFade", p.enableBottomFade),
            ("topFadeHeight", p.topFadeHeight), ("bottomFadeHeight", p.bottomFadeHeight),
            ("showHoverControls", p.showHoverControls), ("hideFromScreenRecording", p.hideFromScreenRecording),
            ("prompterTheme", p.prompterTheme.rawValue), ("backgroundOpacity", p.backgroundOpacity),
            ("horizontalAlignment", p.horizontalAlignment.rawValue), ("textAlignment", p.textAlignment.rawValue),
            ("showProgressBar", p.showProgressBar), ("enableGlobalKeyboardShortcuts", p.enableGlobalKeyboardShortcuts),
            ("speedIncrement", p.speedIncrement), ("manualScrollAmount", p.manualScrollAmount),
        ]
        return values.map { "\($0.0) = \($0.1)" }.joined(separator: "\n")
    }
}

struct NotchShapeTests {
    @Test func theWindowIsTheContentWidenedByAShoulderEachSide() {
        let content = CGRect(x: 100, y: 50, width: 467, height: 260)
        let window = NotchShape.windowFrame(forContent: content)
        #expect(window == CGRect(x: 100 - NotchShape.shoulder, y: 50,
                                 width: 467 + 2 * NotchShape.shoulder, height: 260))
    }

    @Test func theOutlineCoversTheContentAndCutsTheShoulders() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = NotchShape().path(in: rect)
        let s = NotchShape.shoulder
        #expect(path.contains(CGPoint(x: 100, y: 50)))
        #expect(path.contains(CGPoint(x: s - 1, y: 1)))
        #expect(!path.contains(CGPoint(x: 2, y: s - 2)))
        #expect(!path.contains(CGPoint(x: 1, y: 99)))
    }
}
