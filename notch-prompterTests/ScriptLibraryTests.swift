import Dependencies
import Foundation
import Testing
@testable import LafzPrompter

@MainActor
struct ScriptLibraryTests {
    /// The library file, the clipboard and the open panel, kept in memory.
    /// Used only from the main actor.
    final class MemoryFiles: @unchecked Sendable {
        var data: Data?
        var clipboard: (files: [URL], text: String?) = ([], nil)

        var client: ScriptFilesClient {
            ScriptFilesClient(load: { self.data }, save: { self.data = $0 },
                              readClipboard: { self.clipboard }, chooseFiles: { nil })
        }
    }

    private let files = MemoryFiles()

    private let settings = UserDefaults(suiteName: "lafz-library-tests-\(UUID().uuidString)")!

    private func makeLibrary() -> ScriptLibrary {
        withDependencies {
            $0.scriptFiles = files.client
            $0.settingsStorage = settings
        } operation: {
            ScriptLibrary()
        }
    }

    @Test func addingMakesTheScriptCurrentAndSkipsDuplicates() {
        let library = makeLibrary()
        let first = library.add(text: "Hello\nworld", title: nil)
        library.add(text: "Second", title: "Talk")
        #expect(library.current?.title == "Talk")
        library.add(text: "Hello\nworld", title: "Copy")
        #expect(library.scripts.count == 2)
        #expect(library.currentID == first.id)
        #expect(first.title == "Hello")
    }

    @Test func editsUpdateTheCurrentScriptAndItsDerivedTitle() {
        let library = makeLibrary()
        library.add(text: "Old opening", title: nil)
        library.updateCurrent(text: "New opening\nmore")
        #expect(library.current?.title == "New opening")
        #expect(library.current?.text == "New opening\nmore")

        library.add(text: "Named", title: "From file")
        library.updateCurrent(text: "Changed")
        #expect(library.current?.title == "From file")
    }

    @Test func deletingTheCurrentScriptMovesToTheNextAndNeverEmpties() {
        let library = makeLibrary()
        let a = library.add(text: "A", title: nil)
        let b = library.add(text: "B", title: nil)
        library.delete(b.id)
        #expect(library.currentID == a.id)
        library.delete(a.id)
        #expect(library.scripts.count == 1)
        #expect(library.current?.text == "")
    }

    @Test func survivesARestart() {
        let library = makeLibrary()
        library.add(text: "Kept", title: "Keeper")
        library.flush()
        let reopened = makeLibrary()
        #expect(reopened.current?.title == "Keeper")
    }

    @Test func copiedTextBecomesANewScriptAndEmptyClipboardExplainsWhy() {
        let library = makeLibrary()
        files.clipboard = ([], "Copied opening\nmore")
        library.importClipboard()
        #expect(library.current?.title == "Copied opening")
        #expect(library.importError == nil)
        files.clipboard = ([], "   ")
        library.importClipboard()
        #expect(library.importError == "The clipboard has no text in it. Copy your script first.")
        #expect(library.current?.title == "Copied opening")
    }

    @Test func anUpgradeFromBeforeTheLibraryImportsTheScriptKeptInSettings() {
        settings.set("Old opening\nkept before the library", forKey: "PrompterText")
        let library = makeLibrary()
        library.ensureCurrentScript()
        #expect(library.text == "Old opening\nkept before the library")
        #expect(library.scripts.count == 1)
        #expect(!library.scripts.contains { $0.id == ScriptLibrary.tutorialID })
        library.ensureCurrentScript()         // a later launch adds nothing
        #expect(library.scripts.count == 1)
    }

    @Test func aFreshInstallStartsWithTheTutorial() {
        let library = makeLibrary()
        library.ensureCurrentScript()
        #expect(library.current?.id == ScriptLibrary.tutorialID)
        #expect(library.current?.title == "Welcome to Lafz Prompter")
        #expect(library.text == ScriptLibrary.tutorialText)
    }

    @Test func aSavedLibraryIsLeftAsItIs() {
        let first = makeLibrary()
        first.add(text: "My talk", title: nil)
        first.flush()
        settings.set("Old opening", forKey: "PrompterText")
        let library = makeLibrary()
        library.ensureCurrentScript()
        #expect(library.scripts.map(\.text) == ["My talk"])
        #expect(library.text == "My talk")
    }

    @Test func showTutorialAgainAddsItBackOnceAndSelectsIt() {
        let library = makeLibrary()
        library.ensureCurrentScript()
        library.add(text: "My talk", title: nil)
        library.restoreTutorial()
        #expect(library.current?.id == ScriptLibrary.tutorialID)
        #expect(library.scripts.count == 2)
        library.delete(ScriptLibrary.tutorialID)
        library.restoreTutorial()
        #expect(library.current?.id == ScriptLibrary.tutorialID)
        #expect(library.scripts.count == 2)
    }

    @Test func editingTheTextUpdatesTheCurrentScript() {
        let library = makeLibrary()
        library.add(text: "Draft", title: "Talk")
        library.text = "Draft, edited"
        #expect(library.current?.text == "Draft, edited")
        #expect(library.current?.title == "Talk")
    }

    @Test func titlesComeFromTheFirstLine() {
        #expect(ScriptLibrary.title(from: "\n  Intro line \nrest") == "Intro line")
        #expect(ScriptLibrary.title(from: "[slowly]\nFirst words [pause]") == "First words")
        #expect(ScriptLibrary.title(from: "   ") == "Untitled")
        #expect(ScriptLibrary.title(from: String(repeating: "a", count: 60)).count == 41)
    }
}
