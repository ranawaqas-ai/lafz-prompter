import SwiftUI

/// The Script tab: the saved scripts on the left, the current one in the
/// editor on the right. Scripts come in by typing, by Paste, by Open, or by
/// dropping a file anywhere on the tab.
struct ScriptTabView: View {
    @ObservedObject var viewModel: PrompterViewModel
    @Environment(ScriptLibrary.self) private var library
    @FocusState private var isTextEditorFocused: Bool
    @State private var renaming: Script?
    @State private var newTitle = ""
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                scriptList
                    .frame(width: 168)
                editor
            }
            if let error = library.importError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    Button { library.importError = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            library.importFiles(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .alert("Rename Script", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") {
                if let renaming { library.rename(renaming.id, to: newTitle) }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var scriptList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { library.currentID }, set: { if let id = $0 { library.select(id) } })) {
                ForEach(library.scripts) { script in
                    ScriptRow(script: script)
                        .tag(script.id)
                        .contextMenu {
                            Button("Rename…") {
                                newTitle = script.title
                                renaming = script
                            }
                            Button("Delete", role: .destructive) { library.delete(script.id) }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: 14) {
                Button { library.newScript() } label: { Image(systemName: "plus") }
                    .help("New script")
                Button { library.showOpenPanel() } label: { Image(systemName: "folder") }
                    .help("Open a text, Markdown, Word, RTF, HTML or PDF file")
                Button { library.importClipboard() } label: { Image(systemName: "doc.on.clipboard") }
                    .help("New script from the clipboard")
                Spacer()
                if let current = library.current {
                    Button { library.delete(current.id) } label: { Image(systemName: "trash") }
                        .help("Delete this script")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isTextEditorFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isTextEditorFocused ? 2 : 1
                        )
                )
                .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)

            if viewModel.text.isEmpty {
                Text("Type or paste your script, or drop a file here.\n\nUse [brackets] for stage directions like [pause], [smile], etc.")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            HighlightingTextEditor(
                text: $viewModel.text,
                font: .systemFont(ofSize: 15, weight: .regular),
                isFocused: $isTextEditorFocused,
                onFileDrop: { library.importFiles($0) }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}

private struct ScriptRow: View {
    let script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(script.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Text("\(Self.readingTime(script.text)) · \(script.updatedAt.formatted(.relative(presentation: .named)))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    /// At a speaking pace of about 150 words a minute, not counting [cues].
    static func readingTime(_ text: String) -> String {
        let spoken = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        let words = spoken.split(whereSeparator: { $0.isWhitespace }).count
        let seconds = Int((Double(words) / 150 * 60).rounded())
        return seconds < 60 ? "\(max(seconds, words > 0 ? 1 : 0)) sec" : "\((seconds + 30) / 60) min"
    }
}
