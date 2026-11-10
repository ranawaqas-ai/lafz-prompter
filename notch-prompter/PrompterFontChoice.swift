import AppKit

/// Which font the prompter text uses.
enum PrompterFontChoice: Hashable {
    /// Nastaliq for Urdu scripts, the system font for everything else.
    case automatic
    case system
    case custom(String)

    private static let customPrefix = "custom:"

    /// Missing or unreadable values fall back to automatic, as does a font
    /// that has been uninstalled since it was saved.
    init(storageValue: String?) {
        guard let storageValue else {
            self = .automatic
            return
        }
        if storageValue == "system" {
            self = .system
            return
        }
        guard storageValue.hasPrefix(Self.customPrefix) else {
            self = .automatic
            return
        }
        let family = String(storageValue.dropFirst(Self.customPrefix.count))
        self = NSFontManager.shared.availableFontFamilies.contains(family) ? .custom(family) : .automatic
    }

    var storageValue: String {
        switch self {
        case .automatic: return "automatic"
        case .system: return "system"
        case .custom(let family): return Self.customPrefix + family
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}

enum UrduDetector {
    // Letters Urdu uses that Arabic and Persian do not, so those two keep the
    // system font: tte, ddal, rre, noon ghunna, bari ye, do-chashmi he, he goal.
    private static let urduOnlyLetters = CharacterSet(charactersIn: "\u{0679}\u{0688}\u{0691}\u{06BA}\u{06D2}\u{06BE}\u{06C1}")

    private static let nastaliqFamilies = ["Jameel Noori Nastaleeq", "Noto Nastaliq Urdu"]

    /// First installed Nastaliq family, or nil when none is installed.
    static let preferredFontFamily: String? = {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return nastaliqFamilies.first(where: installed.contains)
    }()

    static func containsUrdu(_ text: String) -> Bool {
        text.rangeOfCharacter(from: urduOnlyLetters) != nil
    }
}
