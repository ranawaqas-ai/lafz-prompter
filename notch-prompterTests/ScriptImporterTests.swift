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

    @Test func unwrapsPrintedLines() {
        let pdfText = "The first sentence runs\nacross two lines. Then a hyphen-\nated word.\n\nNew paragraph."
        #expect(ScriptImporter.unwrapLines(pdfText) ==
                "The first sentence runs across two lines. Then a hyphenated word.\n\nNew paragraph.")
    }
}
