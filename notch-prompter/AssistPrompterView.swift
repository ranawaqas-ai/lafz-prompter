import SwiftUI

/// The prompter's content: the script normally, the Call Assist answer while
/// a session is running. The script keeps its place underneath.
struct PrompterRootView: View {
    @ObservedObject var viewModel: PrompterViewModel
    @ObservedObject var callAssist: CallAssistController

    var body: some View {
        ZStack {
            PrompterView(viewModel: viewModel)
            if callAssist.isActive {
                AssistPrompterView(viewModel: viewModel, callAssist: callAssist)
            }
        }
    }
}

/// The detected question in a dim line, the answer streaming beneath it, in
/// the prompter's own font and theme. Follows the end of a long answer.
private struct AssistPrompterView: View {
    @ObservedObject var viewModel: PrompterViewModel
    @ObservedObject var callAssist: CallAssistController

    var body: some View {
        let theme = viewModel.prompterTheme
        ZStack {
            theme.backgroundColor
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: viewModel.lineHeight) {
                        if !callAssist.question.isEmpty {
                            Text(callAssist.question)
                                .font(font(for: callAssist.question, scale: 0.8))
                                .foregroundStyle(theme.textColor.opacity(0.45))
                        }
                        Text(body(theme: theme))
                            .font(font(for: callAssist.answer, scale: 1))
                            .foregroundStyle(theme.textColor)
                            .lineSpacing(viewModel.lineHeight)
                        Color.clear.frame(height: 1).id(Self.bottom)
                    }
                    .multilineTextAlignment(viewModel.textAlignment.swiftUIAlignment)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 32)
                    .padding(.bottom, 12)
                }
                .onChange(of: callAssist.answer) {
                    proxy.scrollTo(Self.bottom, anchor: .bottom)
                }
            }
        }
        .ignoresSafeArea()
    }

    private static let bottom = "bottom"

    private func body(theme: PrompterTheme) -> String {
        if !callAssist.answer.isEmpty { return callAssist.answer }
        switch callAssist.state {
        case .starting: return "Starting Call Assist…"
        case .answering: return "…"
        default: return "Listening for a question…"
        }
    }

    private func font(for text: String, scale: Double) -> Font {
        let size = viewModel.fontSize * scale
        if let family = viewModel.fontFamily(for: text) { return Font.custom(family, fixedSize: size) }
        return scale == 1 ? viewModel.systemFont : .system(size: size)
    }
}
