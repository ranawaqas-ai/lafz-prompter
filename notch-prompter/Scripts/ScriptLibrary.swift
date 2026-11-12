import AppKit
import Observation
import Dependencies

struct Script: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var updatedAt: Date
}

/// Every script the user has loaded, kept in a JSON file so loading a new
/// one never throws the old one away. One script is current: it is the text
/// the prompter shows, and edits to that text are saved back into it.
@MainActor @Observable
final class ScriptLibrary {
    /// Newest edit first.
    private(set) var scripts: [Script] = []
    private(set) var currentID: UUID?
    /// The last import that failed, shown to the user until dismissed.
    var importError: String?

    @ObservationIgnored @Dependency(\.scriptFiles) private var files
    @ObservationIgnored @Dependency(\.settingsStorage) private var settingsStorage
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Whether a library file existed at launch; without one this is a
    /// fresh install or an upgrade from before the library.
    @ObservationIgnored private var foundSavedLibrary = false

    init() {
        load()
    }

    var current: Script? { scripts.first { $0.id == currentID } }

    /// The text the prompter shows: the current script's.
    var text: String {
        get { current?.text ?? "" }
        set { updateCurrent(text: newValue) }
    }

    /// Makes sure a script is current at launch. A saved library is left as
    /// it is. Without one, the script an older version kept in its settings
    /// is imported; with neither, this is a fresh install and the tutorial
    /// becomes the first script.
    func ensureCurrentScript() {
        guard current == nil else { return }
        if foundSavedLibrary {
            if let newest = scripts.first { select(newest.id) }
        } else if let legacy = settingsStorage.string(forKey: Self.legacyTextKey) {
            add(text: legacy, title: nil)
        } else {
            restoreTutorial()
        }
    }

    /// Where the script was kept before the library, read once to import it.
    private static let legacyTextKey = "PrompterText"

    // MARK: Tutorial

    /// The tutorial's fixed id, so it can be found again after edits.
    nonisolated static let tutorialID = UUID(uuidString: "7E1C0A5E-5C41-4B1E-9A2F-3C0D1E7A0001")!
    nonisolated static let tutorialTitle = "Welcome to Lafz Prompter"

    /// Selects the tutorial, adding it back first if it was deleted.
    func restoreTutorial() {
        if !scripts.contains(where: { $0.id == Self.tutorialID }) {
            let tutorial = Script(id: Self.tutorialID, title: Self.tutorialTitle,
                                  text: Self.tutorialText, updatedAt: Date())
            scripts.insert(tutorial, at: 0)
        }
        select(Self.tutorialID)
    }

    /// Teaches the app while it scrolls. Shortcuts written as ⌃⌥P are drawn
    /// as keys in the prompter.
    nonisolated static let tutorialText = """
    Welcome to Lafz Prompter. [smile]
    These words scroll under your notch, right by your camera, so your eyes stay near the lens.

    Press ⌃⌥P to pause me. [try it now]
    Press it again and I'll carry on.

    Too fast or too slow? ⌃⌥→ speeds me up, ⌃⌥← slows me down.
    ⌃⌥↑ and ⌃⌥↓ move back or ahead a few lines.

    Words in brackets are notes for you, not lines to say. [like this one]

    To read your own script, press ⌃⌥O and pick a file: text, Markdown, Word, PDF or a Fountain screenplay.
    Or copy it from anywhere and press ⌃⌥V.

    ⌃⌥H hides me. Press it again to bring me back.

    Forget a shortcut? ⌃⌥/ shows them all.

    Everything else is in the Lafz icon in your menu bar. [look up]
    Can't see it? Open Lafz Prompter again from Applications.

    Rather not press keys? Turn on voice activation and I'll scroll only while you speak.

    That's it. Press ⌃⌥O and load your first script. [smile]
    """

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
        let clipboard = files.readClipboard()
        if !clipboard.files.isEmpty {
            importFiles(clipboard.files)
            return
        }
        let text = ScriptImporter.normalise(clipboard.text ?? "")
        guard !text.isEmpty else {
            importError = "The clipboard has no text in it. Copy your script first."
            return
        }
        importError = nil
        add(text: text, title: nil)
    }

    func showOpenPanel() {
        guard let urls = files.chooseFiles() else { return }
        importFiles(urls)
    }

    // MARK: Managing scripts

    func select(_ id: UUID) {
        guard scripts.contains(where: { $0.id == id }) else { return }
        currentID = id
        save()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].title = trimmed
        save()
    }

    /// Deleting the current script moves to the next one. Deleting the last
    /// leaves the library empty, with no script current.
    func delete(_ id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts.remove(at: index)
        if scripts.isEmpty {
            currentID = nil
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
        guard let data = files.load() else { return }
        foundSavedLibrary = true
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
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
            try files.save(JSONEncoder().encode(Stored(currentID: currentID, scripts: scripts)))
        } catch {
            NSLog("Lafz Prompter could not save scripts: \(error.localizedDescription)")
        }
    }
}
