import AppKit
import Dependencies
import Observation
import SwiftUI

/// How the prompter looks and behaves: every setting the user picks. Each
/// setting is stored under its own UserDefaults key, written only when its
/// value changes.
@MainActor @Observable
final class Preferences {
    // MARK: Text
    var fontSize = 12.0 { didSet { save(fontSize, oldValue, Keys.fontSize) } }
    var lineHeight = 8.0 { didSet { save(lineHeight, oldValue, Keys.lineHeight) } }
    var fontDesign: Font.Design = .monospaced { didSet { save(fontDesign, oldValue, Keys.fontDesign) { $0.rawValue } } }
    var fontChoice: PrompterFontChoice = .automatic { didSet { save(fontChoice, oldValue, Keys.fontChoice) { $0.storageValue } } }
    var textAlignment: PrompterTextAlignment = .center { didSet { save(textAlignment, oldValue, Keys.textAlignment) { $0.rawValue } } }

    // MARK: Look
    var prompterTheme: PrompterTheme = .dark { didSet { save(prompterTheme, oldValue, Keys.prompterTheme) { $0.rawValue } } }
    /// How solid the prompter's background is, from 0.2 to 1. The text stays
    /// fully opaque so it reads over whatever is behind.
    var backgroundOpacity = 1.0 { didSet { save(backgroundOpacity, oldValue, Keys.backgroundOpacity) } }
    var enableTopFade = true { didSet { save(enableTopFade, oldValue, Keys.enableTopFade) } }
    var enableBottomFade = true { didSet { save(enableBottomFade, oldValue, Keys.enableBottomFade) } }
    var topFadeHeight = 40.0 { didSet { save(topFadeHeight, oldValue, Keys.topFadeHeight) } }
    var bottomFadeHeight = 40.0 { didSet { save(bottomFadeHeight, oldValue, Keys.bottomFadeHeight) } }
    var showProgressBar = true { didSet { save(showProgressBar, oldValue, Keys.showProgressBar) } }
    var showHoverControls = true { didSet { save(showHoverControls, oldValue, Keys.showHoverControls) } }

    // MARK: Layout
    var prompterWidth: CGFloat = 184 { didSet { save(prompterWidth, oldValue, Keys.prompterWidth) { Double($0) } } }
    var prompterHeight: CGFloat = 150 { didSet { save(prompterHeight, oldValue, Keys.prompterHeight) { Double($0) } } }
    var horizontalAlignment: PrompterHorizontalAlignment = .center { didSet { save(horizontalAlignment, oldValue, Keys.horizontalAlignment) { $0.rawValue } } }
    var selectedScreenIndex = 0 { didSet { save(selectedScreenIndex, oldValue, Keys.selectedScreenIndex) } }
    var hideFromScreenRecording = false { didSet { save(hideFromScreenRecording, oldValue, Keys.hideFromScreenRecording) } }

    // MARK: Behaviour
    var speed = 12.0 { didSet { save(speed, oldValue, Keys.speed) } }
    var speedIncrement = 2.0 { didSet { save(speedIncrement, oldValue, Keys.speedIncrement) } }
    var manualScrollAmount = 50.0 { didSet { save(manualScrollAmount, oldValue, Keys.manualScrollAmount) } }
    var pauseOnHover = true { didSet { save(pauseOnHover, oldValue, Keys.pauseOnHover) } }
    var voiceActivation = false { didSet { save(voiceActivation, oldValue, Keys.voiceActivation) } }
    var audioThreshold: Float = 0.01 { didSet { save(audioThreshold, oldValue, Keys.audioThreshold) { Double($0) } } }
    var enableGlobalKeyboardShortcuts = true { didSet { save(enableGlobalKeyboardShortcuts, oldValue, Keys.enableGlobalKeyboardShortcuts) } }

    /// True while the user drags a prompter edge: the window then follows the
    /// pointer without animating. Not a setting, so never stored.
    @ObservationIgnored var isResizing = false

    @ObservationIgnored @Dependency(\.settingsStorage) private var defaults
    /// False while the stored values load, so loading writes nothing back.
    @ObservationIgnored private var isLoaded = false

    init() {
        load()
        isLoaded = true
    }

    // MARK: Derived values

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

    var systemFont: Font {
        .system(size: fontSize, weight: .regular, design: fontDesign)
    }

    /// The installed font family a script should be set in, or nil for the system font.
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

    // MARK: Storage

    private enum Keys {
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

    private func save<Value: Equatable>(_ value: Value, _ old: Value, _ key: String,
                                        as stored: (Value) -> Any? = { $0 }) {
        guard isLoaded, value != old else { return }
        defaults.set(stored(value), forKey: key)
    }

    /// Reads every setting. Zero, missing and unknown values fall back to the
    /// defaults, as they always have.
    private func load() {
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

    /// Writes every setting, changed or not. Runs when the app quits, so the
    /// stored set is always complete.
    func saveAll() {
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
