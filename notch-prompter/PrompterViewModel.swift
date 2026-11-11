import Foundation
import Combine
import CoreVideo
import AVFoundation
import Accelerate
import SwiftUI

final class PrompterViewModel: ObservableObject {
    
    // MARK: User settings
    @Published var text: String = """
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
    @Published var isPlaying: Bool = false
    // Kept in its own object: publishing it here would re-render every view
    // observing the view model, including Settings, on every frame of scrolling.
    let scrollPosition = ScrollPosition()
    var offset: CGFloat {
        get { scrollPosition.offset }
        set { scrollPosition.offset = newValue }
    }
    @Published var speed: Double = 12.0
    @Published var fontSize: Double = 10.0
    @Published var lineHeight: Double = 8.0
    @Published var pauseOnHover: Bool = true
    @Published var prompterWidth: CGFloat = 184
    @Published var prompterHeight: CGFloat = 150
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
    @Published var voiceActivation: Bool = false
    /// With voice activation on, whether the mic is running. Play starts it,
    /// Pause, hiding the prompter, Reset, or reaching the end stops it.
    @Published private(set) var isListening: Bool = false
    @Published var autoGain: Bool = false
    @Published var isPrompterVisible: Bool = true
    @Published var fontDesign: Font.Design = .monospaced
    @Published var fontChoice: PrompterFontChoice = .automatic
    @Published var selectedScreenIndex: Int = 0
    @Published var enableTopFade: Bool = true
    @Published var enableBottomFade: Bool = true
    @Published var topFadeHeight: Double = 40.0
    @Published var bottomFadeHeight: Double = 40.0
    @Published var showHoverControls: Bool = true
    @Published var hideFromScreenRecording: Bool = true
    @Published var prompterTheme: PrompterTheme = .dark
    /// How solid the prompter's background is, from 0.2 to 1. The text stays
    /// fully opaque so it reads over whatever is behind.
    @Published var backgroundOpacity: Double = 1.0
    @Published var horizontalAlignment: PrompterHorizontalAlignment = .center
    @Published var textAlignment: PrompterTextAlignment = .center
    @Published var showProgressBar: Bool = true
    @Published var enableGlobalKeyboardShortcuts: Bool = true
    @Published var speedIncrement: Double = 2.0
    @Published var manualScrollAmount: Double = 50.0
    
    var backScrollAmount: Double = 20.0 // pixels to scroll back
    
    
    private var timerCancellable: AnyCancellable?
    private var lastTick: CFTimeInterval?
    private var cancellables: Set<AnyCancellable> = []
    
    var audioMonitor: AudioMonitor?
    private var audioLevelCancellable: AnyCancellable?
    @Published var showMicrophoneAlert: Bool = false
    @Published var audioThreshold: Float = 0.01
    @Published var targetLevel: Double = 0.05  // default 5%

    
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
    
    private let defaults: UserDefaults
    private let shortcuts: GlobalShortcuts

    // MARK: Init
    /// `defaults` and `startsDisplayLink` exist for tests: a separate defaults
    /// suite, and no display link (tests call `tick` with their own times).
    init(defaults: UserDefaults = .standard, startsDisplayLink: Bool = true,
         shortcuts: GlobalShortcuts = GlobalShortcuts()) {
        self.defaults = defaults
        self.shortcuts = shortcuts
        loadSettings()
        if startsDisplayLink { startTimer() }
        observeSettingsChanges()
        $voiceActivation
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self = self else { return }
                // Ask for access now so a denial shows while Settings is open,
                // but the mic only turns on when the user presses Play.
                self.stopListening()
                if enabled {
                    self.withMicrophoneAccess { }
                }
            }
            .store(in: &cancellables)

        $isPrompterVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                if !visible { self?.stopListening() }
            }
            .store(in: &cancellables)
        
        $enableGlobalKeyboardShortcuts
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.shortcuts.set(self.prompterShortcuts, on: enabled)
            }
            .store(in: &cancellables)
    }
    
    private func withMicrophoneAccess(_ action: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            action()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        action()
                    } else {
                        self?.voiceActivation = false
                        self?.showMicrophoneAlert = true
                    }
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
            audioMonitor = AudioMonitor()
        }
        
        // Replace rather than add: each extra subscriber also wrote isPlaying on
        // every audio buffer, so toggling voice activation multiplied UI updates.
        audioLevelCancellable = audioMonitor!.$rmsLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rmsLevel in
                guard let self = self else { return }
                let detected = rmsLevel > self.audioThreshold
                // @Published notifies on every assignment, even of the same value,
                // and each notification re-renders the prompter and Settings.
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
        timerCancellable = CADisplayLinkPublisher()
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
        // A @Published sink runs before the new value is stored, so saving from
        // one wrote the previous value: a pasted script was saved as the text
        // from before the paste. objectWillChange is debounced so the save runs
        // after the change has landed, once per burst of typing.
        objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveSettings() }
            .store(in: &cancellables)
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
    
    // MARK: Connector for display refresh
    private final class CADisplayLinkProxy {
        let subject = PassthroughSubject<CFTimeInterval, Never>()
        var link: CVDisplayLink?
        
        init() {
            var link: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&link)
            self.link = link
            if let l = link {
                CVDisplayLinkSetOutputCallback(l, { (_, _, _, _, _, userInfo) -> CVReturn in
                    let ref = Unmanaged<CADisplayLinkProxy>.fromOpaque(userInfo!).takeUnretainedValue()
                    let ts = CFAbsoluteTimeGetCurrent()
                    DispatchQueue.main.async {
                        ref.subject.send(ts)
                    }
                    return kCVReturnSuccess
                }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
                CVDisplayLinkStart(l)
            }
        }
        
        deinit {
            if let l = link {
                CVDisplayLinkStop(l)
            }
        }
    }
    
    private struct CADisplayLinkPublisher: Publisher {
        typealias Output = CFTimeInterval
        typealias Failure = Never
        
        func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, CFTimeInterval == S.Input {
            let proxy = CADisplayLinkProxy()
            subscriber.receive(subscription: SubscriptionImpl(subscriber: subscriber, proxy: proxy))
        }
        
        private final class SubscriptionImpl<S: Subscriber>: Subscription where S.Input == CFTimeInterval, S.Failure == Never {
            private var subscriber: S?
            private var proxy: CADisplayLinkProxy?
            private var cancellables: Set<AnyCancellable> = []
            
            init(subscriber: S, proxy: CADisplayLinkProxy) {
                self.subscriber = subscriber
                self.proxy = proxy
                
                proxy.subject
                    .sink { [weak self] value in
                        _ = self?.subscriber?.receive(value)
                    }
                    .store(in: &cancellables)
            }
            
            func request(_ demand: Subscribers.Demand) {
                // demand not used
            }
            
            func cancel() {
                subscriber = nil
                proxy = nil
                cancellables.removeAll()
            }
        }
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

final class ScrollPosition: ObservableObject {
    @Published var offset: CGFloat = 0
}
