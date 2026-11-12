import AppKit
import Dependencies

/// Where scripts come from and are kept: the library file, the clipboard and
/// the open panel.
struct ScriptFilesClient: Sendable {
    /// The saved library, or nil when there is none yet.
    var load: @Sendable () -> Data?
    var save: @Sendable (Data) throws -> Void
    /// Copied files, else copied text.
    var readClipboard: @MainActor @Sendable () -> (files: [URL], text: String?)
    /// Asks the user for script files; nil when cancelled.
    var chooseFiles: @MainActor @Sendable () -> [URL]?
}

extension ScriptFilesClient: DependencyKey {
    static var liveValue: ScriptFilesClient { .stored(at: defaultURL) }

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Lafz Prompter", isDirectory: true)
            .appendingPathComponent("scripts.json")
    }

    /// The live client with the library kept at `url`.
    static func stored(at url: URL) -> ScriptFilesClient {
        ScriptFilesClient(
            load: { try? Data(contentsOf: url) },
            save: { data in
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            },
            readClipboard: {
                let pasteboard = NSPasteboard.general
                let files = pasteboard.readObjects(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
                return (files, pasteboard.string(forType: .string))
            },
            chooseFiles: {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = ScriptImporter.contentTypes
                panel.allowsMultipleSelection = true
                panel.message = "Choose a script: text, Markdown, Fountain, Word, RTF, HTML or PDF."
                panel.prompt = "Load"
                // The app is usually in the background behind the menu bar.
                NSApp.activate()
                return panel.runModal() == .OK ? panel.urls : nil
            })
    }
}

extension DependencyValues {
    var scriptFiles: ScriptFilesClient {
        get { self[ScriptFilesClient.self] }
        set { self[ScriptFilesClient.self] = newValue }
    }
}
