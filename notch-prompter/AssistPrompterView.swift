import SwiftUI

/// The prompter's content: the script normally, the Call Assist answer while
/// a session is running. The script keeps its place underneath.
struct PrompterRootView: View {
    @ObservedObject var viewModel: PrompterViewModel
    @ObservedObject var callAssist: CallAssistController

    var body: some View {
        ZStack {
            PrompterView(viewModel: viewModel)
            if callAssist.isActive || callAssist.notice != nil {
                AssistPrompterView(viewModel: viewModel, callAssist: callAssist)
            }
        }
    }
}

/// The detected question in a dim line, the answer streaming beneath it, in
/// the prompter's own font and theme.
private struct AssistPrompterView: View {
    @ObservedObject var viewModel: PrompterViewModel
    @ObservedObject var callAssist: CallAssistController
    @State private var position = SwiftUI.ScrollPosition(edge: .top)
    @State private var offsetY: CGFloat = 0

    var body: some View {
        let theme = viewModel.prompterTheme
        ZStack {
            theme.backgroundColor
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: viewModel.lineHeight) {
                    if !callAssist.question.isEmpty {
                        // One line, keeping the end, which is the actual question.
                        Text(callAssist.question)
                            .font(font(for: callAssist.question, scale: 0.8))
                            .foregroundStyle(theme.textColor.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Text(body(theme: theme))
                        .font(font(for: callAssist.answer, scale: 1))
                        .foregroundStyle(theme.textColor)
                        .lineSpacing(viewModel.lineHeight)
                }
                .multilineTextAlignment(viewModel.textAlignment.swiftUIAlignment)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 12)
            }
            // The answer stays at its start while it streams; the scroll
            // shortcuts and the trackpad move through a long one.
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in offsetY = y }
            .onChange(of: callAssist.scrollNudge) { _, nudge in
                position.scrollTo(y: max(0, offsetY + nudge.delta))
            }
            .onChange(of: callAssist.question) { position.scrollTo(edge: .top) }
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

    private func font(for text: String, scale: Double) -> Font {
        let size = viewModel.fontSize * scale
        if let family = viewModel.fontFamily(for: text) { return Font.custom(family, fixedSize: size) }
        return scale == 1 ? viewModel.systemFont : .system(size: size)
    }
}
