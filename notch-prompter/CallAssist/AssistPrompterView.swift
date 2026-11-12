import SwiftUI

/// The prompter's content: the script normally, the Call Assist answer while
/// a session is running. The script keeps its place underneath.
struct PrompterRootView: View {
    @Environment(CallAssistSession.self) private var callAssist
    @Environment(Playback.self) private var playback
    @Environment(ShortcutGuide.self) private var guide
    @Environment(ScriptLibrary.self) private var library

    var body: some View {
        let showingAssist = callAssist.isActive || callAssist.notice != nil
        let showingList = guide.isOverlayShown
        ZStack {
            // Hidden rather than covered: with a see-through background the
            // script would show through the answer.
            PrompterView()
                .opacity(showingAssist || showingList ? 0 : 1)
            if showingAssist {
                AssistPrompterView()
                    .opacity(showingList ? 0 : 1)
            }
            if showingList {
                ShortcutOverlay()
            } else if showingAssist || !(playback.isFinished || library.current == nil) {
                // The pills are a fixed size, so they have nothing to resize.
                PrompterResizeHandles()
            }
        }
    }
}

/// The detected question in a dim line, the answer streaming beneath it, in
/// the prompter's own font and theme.
private struct AssistPrompterView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(CallAssistSession.self) private var callAssist
    @State private var position = SwiftUI.ScrollPosition(edge: .top)
    @State private var offsetY: CGFloat = 0

    var body: some View {
        let theme = preferences.prompterTheme
        ZStack {
            theme.backgroundColor.opacity(preferences.backgroundOpacity)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: preferences.lineHeight) {
                    if callAssist.isActive || callAssist.answers.count > 1 {
                        HStack(spacing: 6) {
                            if callAssist.isActive {
                                Circle()
                                    .fill(Color(red: 1, green: 0.42, blue: 0.37))
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)
                                Text("Call Assist")
                            }
                            Spacer(minLength: 0)
                            if callAssist.answers.count > 1 {
                                AnswerPager()
                            }
                        }
                        .font(.system(size: max(preferences.fontSize * 0.55, 11), weight: .medium))
                        .foregroundStyle(theme.textColor.opacity(0.62))
                    }
                    if !callAssist.question.isEmpty {
                        // One line, keeping the end, which is the actual question.
                        Text(callAssist.question)
                            .font(font(for: callAssist.question, scale: 0.7))
                            .foregroundStyle(theme.textColor.opacity(0.62))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(AnswerFormatting.segments(body(theme: theme)).enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case .prose(let text):
                            Text(Self.inlineMarkdown(text))
                                .font(font(for: text, scale: 1))
                                .foregroundStyle(theme.textColor)
                                .lineSpacing(preferences.lineHeight)
                        case .code(let language, let code):
                            CodeBlockView(code: code, language: language, theme: theme, fontSize: preferences.fontSize)
                        }
                    }
                }
                .multilineTextAlignment(preferences.textAlignment.swiftUIAlignment)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                // The script starts one blank line below this inset; matching it
                // keeps the first line clear of the notch.
                .padding(.top, 32 + preferences.fontSize * 1.3 + preferences.lineHeight)
                .padding(.bottom, 12)
            }
            // The answer stays at its start while it streams; the scroll
            // shortcuts and the trackpad move through a long one.
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in offsetY = y }
            .onChange(of: callAssist.scrollNudge) { _, nudge in
                position.scrollTo(y: max(0, offsetY + nudge.delta))
            }
            .onChange(of: callAssist.displayedIndex) { position.scrollTo(edge: .top) }
        }
        .ignoresSafeArea()
    }

    private func body(theme: PrompterTheme) -> String {
        if let notice = callAssist.notice { return notice }
        if !callAssist.answer.isEmpty { return callAssist.answer }
        switch callAssist.state {
        case .starting: return "Starting Call Assist…"
        case .answering: return "…"
        default: return "Listening for a question…"
        }
    }

    /// Bold, italics and `inline code` in prose; plain text if it does not parse.
    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func font(for text: String, scale: Double) -> Font {
        let size = preferences.fontSize * scale
        if let family = preferences.fontFamily(for: text) { return Font.custom(family, fixedSize: size) }
        return scale == 1 ? preferences.systemFont : .system(size: size)
    }
}

/// A code block: monospaced, syntax coloured, and scrolling sideways rather
/// than wrapping, so indentation stays readable in a narrow prompter.
private struct CodeBlockView: View {
    let code: String
    let language: String?
    let theme: PrompterTheme
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language {
                Text(language)
                    .font(.system(size: max(fontSize * 0.6, 8), weight: .medium))
                    .foregroundStyle(theme.textColor.opacity(0.45))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                // Tabs as four spaces, and always left-aligned: the prompter's
                // centred alignment would centre each line and wreck indentation.
                Text(SyntaxHighlighter.highlight(code.replacingOccurrences(of: "\t", with: "    "),
                                                 language: language, dark: theme == .dark))
                    .font(.system(size: fontSize * 0.8, design: .monospaced))
                    .foregroundStyle(theme.textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.textColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// "‹ 2 of 5 ›": steps through this session's answers. Control-Option-[ and
/// Control-Option-] do the same from the keyboard.
private struct AnswerPager: View {
    @Environment(CallAssistSession.self) private var callAssist

    var body: some View {
        let index = callAssist.displayedIndex ?? 0
        let count = callAssist.answers.count
        HStack(spacing: 4) {
            Button { callAssist.showPrevious() } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
                .help("Previous answer (⌃⌥[)")
            Text("\(index + 1) of \(count)")
                .monospacedDigit()
            Button { callAssist.showNext() } label: { Image(systemName: "chevron.right") }
                .disabled(index == count - 1)
                .help("Next answer (⌃⌥])")
        }
        .buttonStyle(.plain)
        .opacity(callAssist.viewing == nil ? 0.8 : 1)
        .fixedSize()
    }
}
