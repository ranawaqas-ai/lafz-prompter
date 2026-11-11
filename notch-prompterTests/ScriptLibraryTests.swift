import Foundation
import Testing
@testable import LafzPrompter

@MainActor
struct ScriptLibraryTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("scripts-\(UUID().uuidString).json")

    @Test func addingMakesTheScriptCurrentAndSkipsDuplicates() {
        let library = ScriptLibrary(fileURL: url)
        let first = library.add(text: "Hello\nworld", title: nil)
        library.add(text: "Second", title: "Talk")
        #expect(library.current?.title == "Talk")
        library.add(text: "Hello\nworld", title: "Copy")
        #expect(library.scripts.count == 2)
        #expect(library.currentID == first.id)
        #expect(first.title == "Hello")
    }

    @Test func editsUpdateTheCurrentScriptAndItsDerivedTitle() {
        let library = ScriptLibrary(fileURL: url)
        library.add(text: "Old opening", title: nil)
        library.updateCurrent(text: "New opening\nmore")
        #expect(library.current?.title == "New opening")
        #expect(library.current?.text == "New opening\nmore")

        library.add(text: "Named", title: "From file")
        library.updateCurrent(text: "Changed")
        #expect(library.current?.title == "From file")
    }

    @Test func deletingTheCurrentScriptMovesToTheNextAndNeverEmpties() {
        let library = ScriptLibrary(fileURL: url)
        let a = library.add(text: "A", title: nil)
        let b = library.add(text: "B", title: nil)
        library.delete(b.id)
        #expect(library.currentID == a.id)
        library.delete(a.id)
        #expect(library.scripts.count == 1)
        #expect(library.current?.text == "")
    }

    @Test func survivesARestart() {
        let library = ScriptLibrary(fileURL: url)
        library.add(text: "Kept", title: "Keeper")
        library.flush()
        let reopened = ScriptLibrary(fileURL: url)
        #expect(reopened.current?.title == "Keeper")
        try? FileManager.default.removeItem(at: url)
    }

    @Test func titlesComeFromTheFirstLine() {
        #expect(ScriptLibrary.title(from: "\n  Intro line \nrest") == "Intro line")
        #expect(ScriptLibrary.title(from: "   ") == "Untitled")
        #expect(ScriptLibrary.title(from: String(repeating: "a", count: 60)).count == 41)
    }
}
