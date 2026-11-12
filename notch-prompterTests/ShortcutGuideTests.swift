import AppKit
import Dependencies
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import LafzPrompter

@MainActor
@Suite(.serialized)
struct ShortcutGuideTests {
    typealias Shortcut = GlobalShortcuts.Shortcut

    private final class Fixture {
        let shortcuts = GlobalShortcuts(registersWithSystem: false)
        let playback: Playback
        let guide: ShortcutGuide
        private let suite = "lafz-guide-tests-\(UUID().uuidString)"

        @MainActor
        init() {
            let defaults = UserDefaults(suiteName: suite)!
            let shortcuts = shortcuts
            (playback, guide) = withDependencies {
                $0.globalShortcuts = shortcuts
                $0.settingsStorage = defaults
                $0.frameClock = .stopped
            } operation: {
                let playback = Playback(preferences: Preferences())
                return (playback, ShortcutGuide(playback: playback))
            }
            guide.hintDuration = .milliseconds(50)
            guide.shortcutsEnabled = true
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }
    }

    @Test func aMouseActionShowsTheHintForAMoment() async {
        let app = Fixture()
        app.guide.usedMouse(for: .playPause)
        #expect(app.guide.hint == .playPause)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(app.guide.hint == nil)
    }

    @Test func afterThreePressesTheShortcutIsLearnedAndHintsStop() {
        let app = Fixture()
        app.shortcuts.register(.openScript) {}
        for _ in 0..<ShortcutGuide.learnedAfter { app.shortcuts.press(.openScript) }
        app.guide.usedMouse(for: .openScript)
        #expect(app.guide.hint == nil)
        app.guide.usedMouse(for: .loadClipboard)
        #expect(app.guide.hint == .loadClipboard)
    }

    @Test func pressingTheShortcutClearsItsHint() {
        let app = Fixture()
        app.guide.usedMouse(for: .showHide)
        app.shortcuts.press(.showHide)
        #expect(app.guide.hint == nil)
    }

    @Test func noHintsWhileCallAssistRunsOrWithShortcutsOff() {
        let app = Fixture()
        app.guide.hintsAllowed = false
        app.guide.usedMouse(for: .playPause)
        #expect(app.guide.hint == nil)
        app.guide.hintsAllowed = true
        app.guide.shortcutsEnabled = false
        app.guide.usedMouse(for: .playPause)
        #expect(app.guide.hint == nil)
    }

    @Test func escIsHeldOnlyWhileTheListIsOpen() {
        let app = Fixture()
        #expect(app.shortcuts.registered.contains("⌃⌥/ Show all shortcuts"))
        #expect(!app.shortcuts.registered.contains("Esc Close the shortcut list"))
        app.playback.isPrompterVisible = false
        app.shortcuts.press(.showShortcuts)
        #expect(app.guide.isOverlayShown)
        #expect(app.playback.isPrompterVisible)
        #expect(app.shortcuts.registered.contains("Esc Close the shortcut list"))
        app.shortcuts.press(.closeShortcuts)
        #expect(!app.guide.isOverlayShown)
        #expect(!app.shortcuts.registered.contains("Esc Close the shortcut list"))
    }

    @Test func theListShowsEveryShortcutOnce() {
        let shown = Shortcut.Group.allCases.flatMap { ShortcutList.rows(for: $0) }.flatMap(\.shortcuts)
        let expected = Shortcut.all.filter { $0 != .showShortcuts }
        #expect(shown.count == expected.count)
        #expect(Set(shown) == Set(expected))
    }

    // MARK: Images

    private func render<V: View>(_ view: V, app: Fixture, size: CGSize, named name: String,
                                 testName: String = #function) {
        let fakes = CallAssistSessionCharacterisationTests.self
        let defaults = UserDefaults(suiteName: "lafz-guide-images")!
        let (preferences, library, session) = withDependencies {
            fakes.useFakes(&$0, defaults: defaults, keys: [], listener: fakes.FakeListener(),
                           provider: fakes.FakeProvider([]),
                           history: AnswerHistoryStore(url: FileManager.default.temporaryDirectory
                               .appendingPathComponent("guide-\(UUID().uuidString).sqlite")),
                           shortcuts: GlobalShortcuts(registersWithSystem: false))
            $0.scriptFiles = ScriptLibraryTests.MemoryFiles().client
        } operation: {
            (Preferences(), ScriptLibrary(), CallAssistSession(settings: CallAssistSettings()))
        }
        library.add(text: "Good morning everyone.\nToday I want to share three points.", title: nil)
        let width = size.width + 2 * NotchShape.shoulder
        let hosting = NSHostingView(rootView: NotchPanel { view }
            .environment(preferences)
            .environment(app.playback)
            .environment(library)
            .environment(session)
            .environment(app.guide)
            .frame(width: width, height: size.height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: size.height)
        hosting.appearance = NSAppearance(named: .aqua)
        assertSnapshot(of: hosting, as: .image(precision: 0.98), named: name, testName: testName)
    }

    @Test func approvedShortcutListImage() {
        let app = Fixture()
        render(ShortcutOverlay(), app: app, size: ShortcutOverlay.minimumSize, named: "list")
    }

    @Test func approvedHintImage() {
        let app = Fixture()
        app.guide.hintDuration = .seconds(60)
        app.guide.usedMouse(for: .playPause)
        render(PrompterView(), app: app, size: CGSize(width: 420, height: 180), named: "hint")
    }
}
