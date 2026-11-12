import SwiftUI

// Separate view so scrolling, which only changes the offset, does not rebuild
// the attributed text on every frame.
struct PrompterTextView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ScriptLibrary.self) private var library

    var body: some View {
        movingText
    }

    private var movingText: some View {
        return VStack(spacing: preferences.lineHeight) {
            textBlock
        }
        .padding(.horizontal, 16)
        .padding(.top, 32)
    }

    private var textBlock: some View {
        let base = library.text.isEmpty ? "Put some text in Settings..." : library.text
        let text = "\n" + base + "\n\n[the end]"
        
        return Text(attributedText(from: text))
            .multilineTextAlignment(preferences.textAlignment.swiftUIAlignment)
            .lineSpacing(preferences.lineHeight)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
    }
    
    /// A shortcut written in a script, such as ⌃⌥P, ⌃⌥← or ⌃⌥Return.
    static let keycapPattern = #"⌃⌥(?:Return|Esc|[A-Z0-9]|[←→↑↓\[\]/,.])"#

    /// Pads each shortcut with thin spaces so its key background has room.
    static func paddingKeycaps(in text: String) -> String {
        text.replacingOccurrences(of: keycapPattern, with: "\u{2009}$0\u{2009}", options: .regularExpression)
    }

    private func attributedText(from source: String) -> AttributedString {
        let text = Self.paddingKeycaps(in: source)
        var attributedString = AttributedString(text)
        
        // Default font and color
        // Latin words keep the system font when the script itself is set in another family.
        let fontFamily = preferences.fontFamily(for: text)
        let defaultFont = fontFamily.map { Font.custom($0, fixedSize: preferences.fontSize) } ?? preferences.systemFont
        let defaultColor = preferences.prompterTheme.textColor
        
        // Apply default attributes to entire string
        attributedString.font = defaultFont
        attributedString.foregroundColor = defaultColor
        
        // Find and style text in [brackets]
        let pattern = "\\[[^\\]]+\\]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let range = match.range
                if let stringRange = Range(range, in: text) {
                    let attributedRange = Range(stringRange, in: attributedString)
                    if let attributedRange = attributedRange {
                        // Make annotation text italic and dimmed
                        // Italic on a family without an italic face makes the system
                        // substitute another font, which breaks Nastaliq.
                        attributedString[attributedRange].font = fontFamily == nil ? defaultFont.italic() : defaultFont
                        attributedString[attributedRange].foregroundColor = preferences.prompterTheme.textColor.opacity(0.4)
                    }
                }
            }
        }
        
        // Shortcuts are drawn as keys: a soft box behind the padded token.
        if let regex = try? NSRegularExpression(pattern: "\u{2009}" + Self.keycapPattern + "\u{2009}") {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                guard let stringRange = Range(match.range, in: text),
                      let attributedRange = Range(stringRange, in: attributedString) else { continue }
                attributedString[attributedRange].backgroundColor = defaultColor.opacity(0.16)
            }
        }

        if fontFamily != nil, preferences.fontChoice == .automatic {
            applySystemFontToLatinWords(in: &attributedString, source: text)
        }

        return attributedString
    }

    private func applySystemFontToLatinWords(in attributedString: inout AttributedString, source text: String) {
        guard let regex = try? NSRegularExpression(pattern: "\\p{Latin}[\\p{Latin}\\p{N}'-]*") else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        for match in matches {
            guard let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: attributedString) else { continue }
            attributedString[attributedRange].font = preferences.systemFont
        }
    }
}

// MARK: - Height reader
struct HeightReader: View {
    @Binding var height: CGFloat
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { height = proxy.size.height }
                .onChange(of: proxy.size) { _, newSize in
                    height = newSize.height
                }
        }
    }
}
