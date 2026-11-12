import AVFoundation
import Combine
import Dependencies
import Observation
import SwiftUI

/// The script moving through the prompter: where it is, whether it is
/// playing, voice activation, and the scroll and speed controls. How fast and
/// how far each control moves comes from Preferences.
@MainActor @Observable
final class Playback {
    /// How far the script has scrolled. Changes every frame while playing;
    /// Observation redraws only the views that read it.
    var offset: CGFloat = 0 {
        // Moving back from the end, by any control, leaves the finished state.
        didSet { if isFinished, offset < oldValue { isFinished = false } }
    }
    var isPlaying = false
    /// The script has scrolled to its end and stopped there. The prompter
    /// shrinks to a "Done" pill; Play starts again from the top.
    private(set) var isFinished = false
    /// With voice activation on, whether the mic is running. Play starts it,
    /// Pause, hiding the prompter, Reset, or reaching the end stops it.
    private(set) var isListening = false
    var isPrompterVisible = true {
        didSet { if !isPrompterVisible, oldValue { stopListening() } }
    }
    var showMicrophoneAlert = false
    /// Whether the prompter's global shortcuts are held; the app's setting,
    /// passed on by AppCoordinator.
    var shortcutsEnabled = true {
        didSet { if shortcutsEnabled != oldValue { applyShortcutsSetting() } }
    }

    /// While set, the scroll controls move this instead of the script; Call
    /// Assist uses it for its answer. Takes the distance, negative is up.
    @ObservationIgnored var scrollRedirect: ((CGFloat) -> Void)?
    /// The mic level while listening, for the level meter in Settings.
    @ObservationIgnored private(set) var audioMonitor: AudioMonitor?
    @ObservationIgnored let backScrollAmount = 20.0

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored @Dependency(\.globalShortcuts) private var shortcuts
    @ObservationIgnored @Dependency(\.frameClock) private var frameClock
    @ObservationIgnored @Dependency(\.micPermission) private var micPermission
    @ObservationIgnored @Dependency(\.audioLevels) private var audioLevels

    @ObservationIgnored private var timerCancellable: AnyCancellable?
    @ObservationIgnored private var lastTick: CFTimeInterval?
    @ObservationIgnored private var audioLevelCancellable: AnyCancellable?
    @ObservationIgnored private var voiceActivationTask: Task<Void, Never>?

    init(preferences: Preferences) {
        self.preferences = preferences
        startTimer()
        if preferences.voiceActivation { voiceActivationChanged() }
        applyShortcutsSetting()
        followPreferences()
    }

    // MARK: Playing

    /// Play/Pause from the menu, hotkey, Settings, or hover controls. With voice
    /// activation this starts or stops listening, and speech drives the scrolling.
    func togglePlayback() {
        if isFinished { startOver() }
        if preferences.voiceActivation {
            isListening ? stopListening() : startListening()
        } else {
            isPlaying ? pause() : play()
        }
    }

    func play() {
        if isFinished { startOver() }
        lastTick = nil
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func reset() {
        stopListening()
        isPlaying = false
        offset = 0
        lastTick = nil
        isFinished = false
    }

    /// Called when the text has scrolled past its end.
    func finishScript() {
        stopListening()
        pause()
        isFinished = true
    }

    private func startOver() {
        isFinished = false
        offset = 0
    }

    func tick(current: CFTimeInterval) {
        guard isPlaying else { return }
        let dt = lastTick.map { current - $0 } ?? 0
        lastTick = current
        offset += CGFloat(preferences.speed) * CGFloat(dt)
    }

    private func startTimer() {
        timerCancellable = frameClock.ticks()
            .sink { [weak self] timestamp in self?.tick(current: timestamp) }
    }

    // MARK: Scrolling and speed

    func scrollBack() {
        if let scrollRedirect { return scrollRedirect(-backScrollAmount) }
        offset = max(0, offset - backScrollAmount)
    }

    func scrollUp() {
        if let scrollRedirect { return scrollRedirect(-preferences.manualScrollAmount) }
        offset = max(0, offset - preferences.manualScrollAmount)
    }

    func scrollDown() {
        if let scrollRedirect { return scrollRedirect(preferences.manualScrollAmount) }
        offset += preferences.manualScrollAmount
    }

    func increaseSpeed() {
        preferences.speed = min(40, preferences.speed + preferences.speedIncrement)
    }

    func decreaseSpeed() {
        preferences.speed = max(1, preferences.speed - preferences.speedIncrement)
    }

    // MARK: Voice activation

    func startListening() {
        guard preferences.voiceActivation, isPrompterVisible, !isListening else { return }
        withMicrophoneAccess { [weak self] in
            guard let self, self.preferences.voiceActivation, self.isPrompterVisible, !self.isListening else { return }
            self.monitorAudio()
            self.isListening = true
        }
    }

    /// The user has not answered the microphone question yet, so Settings
    /// explains it before voice activation makes the system ask.
    var microphoneUndecided: Bool { micPermission.status() == .notDetermined }

    func stopListening() {
        guard isListening else { return }
        audioLevelCancellable = nil
        audioMonitor?.stopMonitoring()
        isListening = false
        isPlaying = false
    }

    private func voiceActivationChanged() {
        // Ask for access now so a denial shows while Settings is open,
        // but the mic only turns on when the user presses Play.
        stopListening()
        if preferences.voiceActivation { withMicrophoneAccess { } }
    }

    private func withMicrophoneAccess(_ action: @escaping () -> Void) {
        switch micPermission.status() {
        case .authorized:
            action()
        case .notDetermined:
            let request = micPermission.request
            Task { @MainActor [weak self] in
                if await request() {
                    action()
                } else {
                    self?.microphoneDenied()
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { self.microphoneDenied() }
        @unknown default:
            break
        }
    }

    private func microphoneDenied() {
        preferences.voiceActivation = false
        showMicrophoneAlert = true
    }

    private func monitorAudio() {
        let monitor = audioMonitor ?? audioLevels.makeMonitor()
        audioMonitor = monitor
        // Replace rather than add: each extra subscriber also wrote isPlaying on
        // every audio buffer, so toggling voice activation multiplied UI updates.
        audioLevelCancellable = monitor.$rmsLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rmsLevel in
                guard let self else { return }
                let detected = rmsLevel > self.preferences.audioThreshold
                // Assigning the same value still notifies observers, so only
                // write when the state actually flips.
                guard detected != self.isPlaying else { return }
                if detected { self.lastTick = nil }
                self.isPlaying = detected
            }
        monitor.startMonitoring()
    }

    // MARK: Following preferences

    private var prompterShortcuts: [GlobalShortcuts.Shortcut: () -> Void] {
        [
            .playPause: { [weak self] in self?.togglePlayback() },
            .showHide: { [weak self] in self?.isPrompterVisible.toggle() },
            .faster: { [weak self] in self?.increaseSpeed() },
            .slower: { [weak self] in self?.decreaseSpeed() },
            .scrollUp: { [weak self] in self?.scrollUp() },
            .scrollDown: { [weak self] in self?.scrollDown() },
        ]
    }

    private func applyShortcutsSetting() {
        shortcuts.set(prompterShortcuts, on: shortcutsEnabled)
    }

    /// Voice activation, switched in Settings. The first value is skipped:
    /// init already acted on it.
    private func followPreferences() {
        let preferences = preferences
        voiceActivationTask = Task { [weak self] in
            var last = preferences.voiceActivation
            for await enabled in Observations({ preferences.voiceActivation }) where enabled != last {
                last = enabled
                self?.voiceActivationChanged()
            }
        }
    }
}
