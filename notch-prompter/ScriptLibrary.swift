import AppKit
import Combine

struct Script: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var updatedAt: Date
}

/// Every script the user has loaded, kept in a JSON file so loading a new
/// one never throws the old one away. One script is current: it is the text
/// the prompter shows, and edits to that text are saved back into it.
@MainActor
final class ScriptLibrary: ObservableObject {
    /// Newest edit first.
    @Published private(set) var scripts: [Script] = []
    @Published private(set) var currentID: UUID?
    /// The last import that failed, shown to the user until dismissed.
    @Published var importError: String?

    private let fileURL: URL
    private weak var viewModel: PrompterViewModel?
    private var textObserver: AnyCancellable?
    private var saveTask: Task<Void, Never>?

    nonisolated static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Lafz Prompter", isDirectory: true)
            .appendingPathComponent("scripts.json")
    }

    init(fileURL: URL = ScriptLibrary.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    var current: Script? { scripts.first { $0.id == currentID } }

    /// Keeps the prompter's text and the current script in step. The script
    /// the prompter already shows becomes the first entry of a new library.
    func attach(to viewModel: PrompterViewModel) {
        self.viewModel = viewModel
        if current == nil {
            if let match = scripts.first(where: { $0.text == viewModel.text }) {
                currentID = match.id
            } else {
                add(text: viewModel.text, title: nil)
            }
        }
        if let current, current.text != viewModel.text { viewModel.text = current.text }
        textObserver = viewModel.$text
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] text in self?.updateCurrent(text: text) }
    }

    // MARK: Loading scripts

    /// Adds a script and makes it current. Text already in the library is
    /// selected instead of copied.
    @discardableResult
    func add(text: String, title: String?) -> Script {
        if let existing = scripts.first(where: { $0.text == text }) {
            select(existing.id)
            return existing
        }
        let script = Script(id: UUID(), title: title ?? Self.title(from: text), text: text, updatedAt: Date())
        scripts.insert(script, at: 0)
        select(script.id)
        save()
        return script
    }

    func newScript() {
        let script = Script(id: UUID(), title: "Untitled", text: "", updatedAt: Date())
        scripts.insert(script, at: 0)
        select(script.id)
        save()
    }

    /// Reads each file and adds it; the last one read becomes current.
    func importFiles(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            do {
                add(text: try ScriptImporter.read(url), title: ScriptImporter.title(for: url))
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        importError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    /// A copied file is imported; copied text becomes a new script.
    func importClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            importFiles(urls)
            return
        }
        let text = ScriptImporter.normalise(pasteboard.string(forType: .string) ?? "")
        guard !text.isEmpty else {
            importError = "The clipboard has no text in it. Copy your script first."
            return
        }
        importError = nil
        add(text: text, title: nil)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ScriptImporter.contentTypes
        panel.allowsMultipleSelection = true
        panel.message = "Choose a script: text, Markdown, Word, RTF, HTML or PDF."
        panel.prompt = "Load"
        // The app is usually in the background behind the menu bar.
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    // MARK: Managing scripts

    func select(_ id: UUID) {
        guard let script = scripts.first(where: { $0.id == id }) else { return }
        // An edit still inside the debounce belongs to the script being left.
        if let viewModel, currentID != id { updateCurrent(text: viewModel.text) }
        currentID = id
        save()
        guard let viewModel else { return }
        if viewModel.text != script.text {
            viewModel.text = script.text
            viewModel.reset()
        }
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].title = trimmed
        save()
    }

    /// Deleting the current script moves to the next one; the library is
    /// never left empty.
    func delete(_ id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts.remove(at: index)
        if scripts.isEmpty {
            newScript()
        } else if currentID == id {
            select(scripts[min(index, scripts.count - 1)].id)
        }
        save()
    }

    func updateCurrent(text: String) {
        guard let index = scripts.firstIndex(where: { $0.id == currentID }),
              scripts[index].text != text else { return }
        var script = scripts.remove(at: index)
        if script.title == "Untitled" || script.title == Self.title(from: script.text) {
            script.title = Self.title(from: text)
        }
        script.text = text
        script.updatedAt = Date()
        scripts.insert(script, at: 0)
        save()
    }

    /// The first spoken line, shortened, for scripts that came without a file
    /// name. [Stage directions] are skipped, since they are not said aloud.
    static func title(from text: String) -> String {
        let line = text
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !line.isEmpty else { return "Untitled" }
        return line.count > 40 ? line.prefix(40).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    // MARK: Storage

    private struct Stored: Codable {
        var currentID: UUID?
        var scripts: [Script]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        scripts = stored.scripts.sorted { $0.updatedAt > $1.updatedAt }
        currentID = stored.currentID
    }

    /// Writes after a short pause, so typing does not rewrite the file on
    /// every keystroke. `flush` writes straight away.
    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Stored(currentID: currentID, scripts: scripts))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Lafz Prompter could not save scripts: \(error.localizedDescription)")
        }
    }
}
