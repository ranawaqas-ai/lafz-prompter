import Foundation
import Combine
import Observation
import CoreVideo
import AVFoundation
import Accelerate
import SwiftUI
import Dependencies

@MainActor @Observable
final class PrompterViewModel {
    
    // MARK: User settings
    var text: String = """
    This is a scrolling text test for Lafz Prompter for macOS.
    The purpose of this demo is to check speed, readability, and smoothness. [pause]
    Adjust the font size, scroll speed, and window opacity to your preference.  
    Keep your eyes on the notch and follow the moving line.

    Good morning everyone. [smile] Today I want to share a few key points about our upcoming product launch.
    First, we focused on reducing complexity and delivering a clean, intuitive user experience.
    Second, we significantly improved performance, ensuring that the application runs smoothly even under heavy load. [gesture to screen]
    Finally, we are excited to begin our rollout strategy and gather feedback from early adopters.
    Thank you for your time, and let's begin. [nod]

    You are capable of more than you think.  
    Every step forward, no matter how small, builds momentum.  
    Stay focused, stay consistent, and trust the process. [pause]
    Progress is progress, even if no one else sees it.  
    Keep going — your future self will thank you.
    
    In the rapidly evolving world of technology, the ability to adapt and learn quickly has become more important than ever.
    Teams and individuals who embrace experimentation, curiosity, and continuous improvement tend to outperform those who rely on rigid structures and outdated processes.
    Innovation rarely comes from doing the same thing repeatedly. [emphasize] Instead, it thrives in environments where people feel safe to explore new ideas, challenge assumptions, and iterate rapidly.
    As we move into the next phase of development, our focus should remain on collaboration, communication, and execution.
    By aligning our goals and maintaining a clear vision, we can build products that not only solve real problems but also inspire and empower the people who use them.
    Let’s continue pushing boundaries and striving for excellence.
    """
    var isPlaying: Bool = false
    /// How far the script has scrolled. Changes every frame while playing;
    /// Observation redraws only the views that read it.
    var offset: CGFloat = 0
    var speed: Double = 12.0
    var fontSize: Double = 10.0
    var lineHeight: Double = 8.0
    var pauseOnHover: Bool = true
    var prompterWidth: CGFloat = 184
    var prompterHeight: CGFloat = 150
    /// The screen the prompter sits on: the chosen one, or the main screen.
    var prompterScreen: NSScreen? {
        let screens = NSScreen.screens
        return screens.indices.contains(selectedScreenIndex) ? screens[selectedScreenIndex] : NSScreen.main
    }

    /// Allowed prompter width: up to the screen width less the 20 px margin
    /// the window keeps on each side.
    var prompterWidthRange: ClosedRange<CGFloat> {
        150...max(150, (prompterScreen?.frame.width ?? 600) - 40)
    }

    /// Allowed prompter height: up to the full screen height.
    var prompterHeightRange: ClosedRange<CGFloat> {
        80...max(80, prompterScreen?.frame.height ?? 500)
    }

    /// True while the user drags the prompter's bottom edge; the window then
    /// follows the pointer without animating.
    var isResizing = false
    var voiceActivation: Bool = false {
        didSet { if isLoaded, voiceActivation != oldValue { voiceActivationChanged() } }
    }
    /// With voice activation on, whether the mic is running. Play starts it,
    /// Pause, hiding the prompter, Reset, or reaching the end stops it.
    private(set) var isListening: Bool = false
    var autoGain: Bool = false
    var isPrompterVisible: Bool = true {
        didSet { if isLoaded, !isPrompterVisible, oldValue { stopListening() } }
    }
    var fontDesign: Font.Design = .monospaced
    var fontChoice: PrompterFontChoice = .automatic
    var selectedScreenIndex: Int = 0
    var enableTopFade: Bool = true
    var enableBottomFade: Bool = true
    var topFadeHeight: Double = 40.0
    var bottomFadeHeight: Double = 40.0
    var showHoverControls: Bool = true
    var hideFromScreenRecording: Bool = true
    var prompterTheme: PrompterTheme = .dark
    /// How solid the prompter's background is, from 0.2 to 1. The text stays
    /// fully opaque so it reads over whatever is behind.
    var backgroundOpacity: Double = 1.0
    var horizontalAlignment: PrompterHorizontalAlignment = .center
    var textAlignment: PrompterTextAlignment = .center
    var showProgressBar: Bool = true
    var enableGlobalKeyboardShortcuts: Bool = true {
        didSet { if isLoaded, enableGlobalKeyboardShortcuts != oldValue { applyShortcutsSetting() } }
    }
    var speedIncrement: Double = 2.0
    var manualScrollAmount: Double = 50.0
    
    @ObservationIgnored var backScrollAmount: Double = 20.0 // pixels to scroll back
    
    
    @ObservationIgnored private var timerCancellable: AnyCancellable?
    @ObservationIgnored private var lastTick: CFTimeInterval?
    
    @ObservationIgnored var audioMonitor: AudioMonitor?
    @ObservationIgnored private var audioLevelCancellable: AnyCancellable?
    var showMicrophoneAlert: Bool = false
    var audioThreshold: Float = 0.01
    var targetLevel: Double = 0.05  // default 5%

    
    // MARK: UserDefaults keys
    private enum Keys {
        static let text = "PrompterText"
        static let speed = "PrompterSpeed"
        static let fontSize = "PrompterFontSize"
        static let lineHeight = "PrompterLineHeight"
        static let pauseOnHover = "PrompterPauseOnHover"
        static let prompterWidth = "PrompterWidth"
        static let prompterHeight = "PrompterHeight"
        static let voiceActivation = "VoiceActivation"
        static let audioThreshold = "AudioThreshold"
        static let fontDesign = "FontDesign"
        static let fontChoice = "FontChoice"
        static let selectedScreenIndex = "SelectedScreenIndex"
        static let enableTopFade = "EnableTopFade"
        static let enableBottomFade = "EnableBottomFade"
        static let topFadeHeight = "TopFadeHeight"
        static let bottomFadeHeight = "BottomFadeHeight"
        static let showHoverControls = "ShowHoverControls"
        static let hideFromScreenRecording = "HideFromScreenRecording"
        static let prompterTheme = "PrompterTheme"
        static let backgroundOpacity = "PrompterBackgroundOpacity"
        static let horizontalAlignment = "HorizontalAlignment"
        static let textAlignment = "TextAlignment"
        static let showProgressBar = "ShowProgressBar"
        static let enableGlobalKeyboardShortcuts = "EnableGlobalKeyboardShortcuts"
        static let speedIncrement = "SpeedIncrement"
        static let manualScrollAmount = "ManualScrollAmount"
    }
    
    // MARK: Services
    @ObservationIgnored @Dependency(\.settingsStorage) private var defaults
    @ObservationIgnored @Dependency(\.globalShortcuts) private var shortcuts
    @ObservationIgnored @Dependency(\.frameClock) private var frameClock
    @ObservationIgnored @Dependency(\.micPermission) private var micPermission
    @ObservationIgnored @Dependency(\.audioLevels) private var audioLevels

    // MARK: Init
    init() {
        loadSettings()
        startTimer()
        observeSettingsChanges()
        isLoaded = true
        // What the property observers do on a change, once for the loaded values.
        if voiceActivation { voiceActivationChanged() }
        applyShortcutsSetting()
    }

    /// False while the stored settings load, so the property observers act
    /// only on changes made after launch.
    @ObservationIgnored private var isLoaded = false

    private func voiceActivationChanged() {
        // Ask for access now so a denial shows while Settings is open,
        // but the mic only turns on when the user presses Play.
        stopListening()
        if voiceActivation { withMicrophoneAccess { } }
    }

    private func applyShortcutsSetting() {
        shortcuts.set(prompterShortcuts, on: enableGlobalKeyboardShortcuts)
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
                    self?.voiceActivation = false
                    self?.showMicrophoneAlert = true
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.voiceActivation = false
                self.showMicrophoneAlert = true
            }
        @unknown default:
            break
        }
    }

    
    func startListening() {
        guard voiceActivation, isPrompterVisible, !isListening else { return }
        withMicrophoneAccess { [weak self] in
            guard let self, self.voiceActivation, self.isPrompterVisible, !self.isListening else { return }
            self.monitorAudio()
            self.isListening = true
        }
    }

    func stopListening() {
        guard isListening else { return }
        audioLevelCancellable = nil
        audioMonitor?.stopMonitoring()
        isListening = false
        isPlaying = false
    }

    /// Play/Pause from the menu, hotkey, Settings, or hover controls. With voice
    /// activation this starts or stops listening, and speech drives the scrolling.
    func togglePlayback() {
        if voiceActivation {
            isListening ? stopListening() : startListening()
        } else {
            isPlaying ? pause() : play()
        }
    }

    /// Called when the text has scrolled past its end.
    func finishScript() {
        stopListening()
        pause()
    }

    private func monitorAudio() {
        if(audioMonitor == nil){
            audioMonitor = audioLevels.makeMonitor()
        }
        
        // Replace rather than add: each extra subscriber also wrote isPlaying on
        // every audio buffer, so toggling voice activation multiplied UI updates.
        audioLevelCancellable = audioMonitor!.$rmsLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rmsLevel in
                guard let self = self else { return }
                let detected = rmsLevel > self.audioThreshold
                // Assigning the same value still notifies observers, so only
                // write when the state actually flips.
                guard detected != self.isPlaying else { return }
                if detected {
                    self.lastTick = nil
                }
                self.isPlaying = detected
            }

        audioMonitor!.startMonitoring()
    }

    
    // MARK: Play/Pause
    var systemFont: Font {
        .system(size: fontSize, weight: .regular, design: fontDesign)
    }

    /// The installed font family the script should be set in, or nil for the system font.
    func fontFamily(for script: String) -> String? {
        switch fontChoice {
        case .system:
            return nil
        case .custom(let family):
            return family
        case .automatic:
            return UrduDetector.containsUrdu(script) ? UrduDetector.preferredFontFamily : nil
        }
    }

    func play() {
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
    }
    
    /// While set, the scroll controls move this instead of the script; Call
    /// Assist uses it for its answer. Takes the distance, negative is up.
    var scrollRedirect: ((CGFloat) -> Void)?

    func scrollBack() {
        if let scrollRedirect { return scrollRedirect(-backScrollAmount) }
        offset = max(0, offset - backScrollAmount)
    }
    
    // MARK: Manual Scroll Control
    func scrollUp() {
        if let scrollRedirect { return scrollRedirect(-manualScrollAmount) }
        offset = max(0, offset - manualScrollAmount)
    }
    
    func scrollDown() {
        if let scrollRedirect { return scrollRedirect(manualScrollAmount) }
        offset += manualScrollAmount
    }
    
    // MARK: Speed Control
    func increaseSpeed() {
        speed = min(40, speed + speedIncrement)
    }
    
    func decreaseSpeed() {
        speed = max(1, speed - speedIncrement)
    }
    
    // MARK: Global keyboard shortcuts
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

    // MARK: Timer
    private func startTimer() {
        timerCancellable = frameClock.ticks()
            .sink { [weak self] timestamp in
                self?.tick(current: timestamp)
            }
    }
    
    func tick(current: CFTimeInterval) {
        guard isPlaying else { return }
        
        let dt: CFTimeInterval
        if let last = lastTick {
            dt = current - last
        } else {
            dt = 0
        }
        lastTick = current
        
        offset += CGFloat(speed) * CGFloat(dt)
    }
    
    // MARK: Settings persistence
    private func observeSettingsChanges() {
        // Observation reports a change before the new value is stored, so the
        // save runs on a later turn, debounced to once per burst of typing.
        withObservationTracking { readSavedState() } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleSave()
                self?.observeSettingsChanges()
            }
        }
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveSettings()
        }
    }

    /// Every property whose change triggers a save. Play and pause count, as
    /// they did before Observation; the split of this type stops that.
    private func readSavedState() {
        _ = (text, isPlaying, speed, fontSize, lineHeight, pauseOnHover, prompterWidth, prompterHeight, voiceActivation, isListening, autoGain, isPrompterVisible, fontDesign, fontChoice, selectedScreenIndex, enableTopFade, enableBottomFade, topFadeHeight, bottomFadeHeight, showHoverControls, hideFromScreenRecording, prompterTheme, backgroundOpacity, horizontalAlignment, textAlignment, showProgressBar, enableGlobalKeyboardShortcuts, speedIncrement, manualScrollAmount, showMicrophoneAlert, audioThreshold, targetLevel)
    }
    
    private func loadSettings() {
        
        text = defaults.string(forKey: Keys.text) ?? text
        speed = defaults.double(forKey: Keys.speed)
        if speed == 0 { speed = 12.0 }
        fontSize = defaults.double(forKey: Keys.fontSize)
        if fontSize == 0 { fontSize = 12.0 }
        lineHeight = defaults.double(forKey: Keys.lineHeight)
        if lineHeight == 0 { lineHeight = 8.0 }
        pauseOnHover = defaults.object(forKey: Keys.pauseOnHover) as? Bool ?? true
        prompterWidth = CGFloat(defaults.double(forKey: Keys.prompterWidth))
        if prompterWidth == 0 { prompterWidth = 184 }
        prompterHeight = CGFloat(defaults.double(forKey: Keys.prompterHeight))
        if prompterHeight == 0 { prompterHeight = 150 }
        voiceActivation = defaults.object(forKey: Keys.voiceActivation) as? Bool ?? false
        let threshold = defaults.double(forKey: Keys.audioThreshold)
        audioThreshold = threshold == 0 ? 0.01 : Float(threshold)
        
        if let fontDesignRaw = defaults.string(forKey: Keys.fontDesign) {
            fontDesign = Font.Design(rawValue: fontDesignRaw) ?? .default
        }
        fontChoice = PrompterFontChoice(storageValue: defaults.string(forKey: Keys.fontChoice))
        
        selectedScreenIndex = defaults.integer(forKey: Keys.selectedScreenIndex)
        
        enableTopFade = defaults.object(forKey: Keys.enableTopFade) as? Bool ?? true
        enableBottomFade = defaults.object(forKey: Keys.enableBottomFade) as? Bool ?? true
        topFadeHeight = defaults.double(forKey: Keys.topFadeHeight)
        if topFadeHeight == 0 { topFadeHeight = 40.0 }
        bottomFadeHeight = defaults.double(forKey: Keys.bottomFadeHeight)
        if bottomFadeHeight == 0 { bottomFadeHeight = 40.0 }
        showHoverControls = defaults.object(forKey: Keys.showHoverControls) as? Bool ?? true
        hideFromScreenRecording = defaults.object(forKey: Keys.hideFromScreenRecording) as? Bool ?? false
        
        if let themeRaw = defaults.string(forKey: Keys.prompterTheme) {
            prompterTheme = PrompterTheme(rawValue: themeRaw) ?? .dark
        }
        backgroundOpacity = defaults.object(forKey: Keys.backgroundOpacity) as? Double ?? 1.0
        
        if let horizontalAlignRaw = defaults.string(forKey: Keys.horizontalAlignment) {
            horizontalAlignment = PrompterHorizontalAlignment(rawValue: horizontalAlignRaw) ?? .center
        }
        
        if let textAlignRaw = defaults.string(forKey: Keys.textAlignment) {
            textAlignment = PrompterTextAlignment(rawValue: textAlignRaw) ?? .center
        }
        
        showProgressBar = defaults.object(forKey: Keys.showProgressBar) as? Bool ?? true
        
        enableGlobalKeyboardShortcuts = defaults.object(forKey: Keys.enableGlobalKeyboardShortcuts) as? Bool ?? true
        speedIncrement = defaults.double(forKey: Keys.speedIncrement)
        if speedIncrement == 0 { speedIncrement = 2.0 }
        manualScrollAmount = defaults.double(forKey: Keys.manualScrollAmount)
        if manualScrollAmount == 0 { manualScrollAmount = 50.0 }
    }
    
    func saveSettings() {
        defaults.set(text, forKey: Keys.text)
        defaults.set(speed, forKey: Keys.speed)
        defaults.set(fontSize, forKey: Keys.fontSize)
        defaults.set(lineHeight, forKey: Keys.lineHeight)
        defaults.set(pauseOnHover, forKey: Keys.pauseOnHover)
        defaults.set(Double(prompterWidth), forKey: Keys.prompterWidth)
        defaults.set(Double(prompterHeight), forKey: Keys.prompterHeight)
        defaults.set(voiceActivation, forKey: Keys.voiceActivation)
        defaults.set(Double(audioThreshold), forKey: Keys.audioThreshold)
        defaults.set(fontDesign.rawValue, forKey: Keys.fontDesign)
        defaults.set(fontChoice.storageValue, forKey: Keys.fontChoice)
        defaults.set(selectedScreenIndex, forKey: Keys.selectedScreenIndex)
        defaults.set(enableTopFade, forKey: Keys.enableTopFade)
        defaults.set(enableBottomFade, forKey: Keys.enableBottomFade)
        defaults.set(topFadeHeight, forKey: Keys.topFadeHeight)
        defaults.set(bottomFadeHeight, forKey: Keys.bottomFadeHeight)
        defaults.set(showHoverControls, forKey: Keys.showHoverControls)
        defaults.set(hideFromScreenRecording, forKey: Keys.hideFromScreenRecording)
        defaults.set(prompterTheme.rawValue, forKey: Keys.prompterTheme)
        defaults.set(backgroundOpacity, forKey: Keys.backgroundOpacity)
        defaults.set(horizontalAlignment.rawValue, forKey: Keys.horizontalAlignment)
        defaults.set(textAlignment.rawValue, forKey: Keys.textAlignment)
        defaults.set(showProgressBar, forKey: Keys.showProgressBar)
        defaults.set(enableGlobalKeyboardShortcuts, forKey: Keys.enableGlobalKeyboardShortcuts)
        defaults.set(speedIncrement, forKey: Keys.speedIncrement)
        defaults.set(manualScrollAmount, forKey: Keys.manualScrollAmount)
    }
}
// MARK: - Font.Design Extension for UserDefaults
extension Font.Design: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "default": self = .default
        case "serif": self = .serif
        case "rounded": self = .rounded
        case "monospaced": self = .monospaced
        default: return nil
        }
    }
    
    public var rawValue: String {
        switch self {
        case .default: return "default"
        case .serif: return "serif"
        case .rounded: return "rounded"
        case .monospaced: return "monospaced"
        @unknown default: return "default"
        }
    }
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        case .monospaced: return "Monospaced"
        @unknown default: return "Default"
        }
    }
    
    var icon: String {
        switch self {
        case .default: return "Aa"
        case .serif: return "Aa"
        case .rounded: return "Aa"
        case .monospaced: return "Aa"
        @unknown default: return "Aa"
        }
    }
    
    var previewFont: Font {
        switch self {
        case .default: return .system(size: 20, weight: .medium, design: .default)
        case .serif: return .system(size: 20, weight: .medium, design: .serif)
        case .rounded: return .system(size: 20, weight: .medium, design: .rounded)
        case .monospaced: return .system(size: 20, weight: .medium, design: .monospaced)
        @unknown default: return .system(size: 20, weight: .medium, design: .default)
        }
    }
}

// MARK: - PrompterTheme Enum
enum PrompterTheme: String, CaseIterable {
    case dark = "dark"
    case light = "light"
    
    var displayName: LocalizedStringKey {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .dark: return .black
        case .light: return .white
        }
    }
    
    var textColor: Color {
        switch self {
        case .dark: return .white
        case .light: return .black
        }
    }
    
    var fadeColor: Color {
        switch self {
        case .dark: return .black
        case .light: return .white
        }
    }
}

// MARK: - PrompterHorizontalAlignment Enum
enum PrompterHorizontalAlignment: String, CaseIterable {
    case left = "left"
    case center = "center"
    case right = "right"
    
    var displayName: LocalizedStringKey {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }
    
    var icon: String {
        switch self {
        case .left: return "arrow.left.to.line"
        case .center: return "arrow.left.and.right"
        case .right: return "arrow.right.to.line"
        }
    }
}

// MARK: - PrompterTextAlignment Enum
enum PrompterTextAlignment: String, CaseIterable {
    case leading = "leading"
    case center = "center"
    case trailing = "trailing"
    
    var displayName: LocalizedStringKey {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }
    
    var icon: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }
    
    var swiftUIAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
