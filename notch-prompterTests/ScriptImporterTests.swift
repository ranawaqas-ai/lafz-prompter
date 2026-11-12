import AppKit
import Foundation
import Testing
@testable import LafzPrompter

struct ScriptImporterTests {
    private func write(_ data: Data, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("script-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }

    @Test func readsPlainTextAndTidiesWhitespace() throws {
        let url = try write(Data("Hello there.  \r\n\r\n\r\n\r\nSecond line.\n\n".utf8), ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ScriptImporter.read(url) == "Hello there.\n\nSecond line.")
    }

    @Test func stripsMarkdownButKeepsStageDirections() throws {
        let markdown = """
        # Launch talk

        - **Welcome** everyone [smile]
        - See [our site](https://example.com) and *thank* you
        > Quote `here`
        """
        let url = try write(Data(markdown.utf8), ext: "md")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ScriptImporter.read(url) == """
        Launch talk

        Welcome everyone [smile]
        See our site and thank you
        Quote here
        """)
    }

    @Test func readsRichText() throws {
        let attributed = NSAttributedString(string: "Bold opening.\nSecond line.",
                                            attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let url = try write(data, ext: "rtf")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ScriptImporter.read(url) == "Bold opening.\nSecond line.")
    }

    @Test func readsWordDocuments() throws {
        let attributed = NSAttributedString(string: "From Word.")
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        let url = try write(data, ext: "docx")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ScriptImporter.read(url) == "From Word.")
    }

    @Test func rejectsUnknownAndEmptyFiles() throws {
        let image = try write(Data([0x89, 0x50]), ext: "png")
        let empty = try write(Data("  \n ".utf8), ext: "txt")
        defer {
            try? FileManager.default.removeItem(at: image)
            try? FileManager.default.removeItem(at: empty)
        }
        #expect(throws: ScriptImporter.ImportError.self) { try ScriptImporter.read(image) }
        #expect(throws: ScriptImporter.ImportError.self) { try ScriptImporter.read(empty) }
    }

    @Test func readsOnlyTheDialogueOfAFountainScreenplay() throws {
        let fountain = """
        Title: Launch Video
        Author: Someone
            Second author line

        INT. HOME OFFICE - DAY

        Waqas sits at the desk, laptop open.

        WAQAS
        Hi, I'm *Waqas*, and this is **Lafz Prompter**.

        WAQAS (CONT'D)
        (smiling)
        It hides under your _notch_.

        [[pause for the screen recording]]

        @McCLANE ^
        Nice. /* cut this joke */

        # Act two
        = The ending

        CUT TO:

        EXT. STREET - NIGHT

        WAQAS
        Bye.
        """
        let url = try write(Data(fountain.utf8), ext: "fountain")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ScriptImporter.read(url) == """
        [WAQAS]
        Hi, I'm Waqas, and this is Lafz Prompter.

        [smiling]
        It hides under your notch.

        [pause for the screen recording]

        [McCLANE]
        Nice.

        [WAQAS]
        Bye.
        """)
    }

    @Test func aSingleSpeakerFountainScriptHasNoNameCues() {
        let fountain = "INT. STUDIO - DAY\n\nHOST\nWelcome back.\n\nHOST\n(beat)\nLet's begin."
        #expect(Fountain.script(from: fountain) == "Welcome back.\n\n[beat]\nLet's begin.")
    }

    @Test func aFountainFileWithoutDialogueKeepsItsAction() {
        let fountain = "Title: Notes\n\n.OPENING\n\nThis is narration.\n\n>Centred line<\n\nFADE OUT."
        #expect(Fountain.script(from: fountain) == "This is narration.\n\nCentred line\n\nFADE OUT.")
    }

    @Test func unwrapsPrintedLines() {
        let pdfText = "The first sentence runs\nacross two lines. Then a hyphen-\nated word.\n\nNew paragraph."
        #expect(ScriptImporter.unwrapLines(pdfText) ==
                "The first sentence runs across two lines. Then a hyphenated word.\n\nNew paragraph.")
    }
}

struct KeycapTests {
    @Test func shortcutsInAScriptArePaddedAsKeys() {
        let padded = PrompterTextView.paddingKeycaps(in: "Press ⌃⌥P, ⌃⌥← or ⌃⌥Return. Not ⌃ alone, nor ⌥x.")
        #expect(padded == "Press \u{2009}⌃⌥P\u{2009}, \u{2009}⌃⌥←\u{2009} or \u{2009}⌃⌥Return\u{2009}. Not ⌃ alone, nor ⌥x.")
    }

    @Test func everyShortcutInTheTutorialIsRecognised() {
        let tutorial = ScriptLibrary.tutorialText
        let written = tutorial.components(separatedBy: "⌃⌥").count - 1
        let matched = PrompterTextView.paddingKeycaps(in: tutorial).components(separatedBy: "\u{2009}⌃⌥").count - 1
        #expect(written == matched)
    }
}
