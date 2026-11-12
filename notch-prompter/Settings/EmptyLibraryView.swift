import SwiftUI

/// The Script tab with no scripts: the whole pane takes a dropped file, with
/// buttons for the other ways in and a link back to the tutorial.
struct EmptyLibraryView: View {
    @Environment(ScriptLibrary.self) private var library

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop a script here")
                .font(.system(size: 15, weight: .semibold))
            Text("Text, Markdown, Word, PDF or Fountain")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    library.showOpenPanel()
                } label: {
                    HStack(spacing: 6) {
                        Text("Open File…")
                        KeycapLabel(GlobalShortcuts.Shortcut.openScript.label)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button {
                    library.importClipboard()
                } label: {
                    HStack(spacing: 6) {
                        Text("Paste")
                        KeycapLabel(GlobalShortcuts.Shortcut.loadClipboard.label)
                    }
                }
                Button {
                    library.newScript()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New blank script")
                .accessibilityLabel("New blank script")
            }
            .padding(.top, 6)
            Button("Play the tutorial again") { library.restoreTutorial() }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
    }
}
