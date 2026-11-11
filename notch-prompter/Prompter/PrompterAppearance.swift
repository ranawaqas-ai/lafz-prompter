import SwiftUI

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
