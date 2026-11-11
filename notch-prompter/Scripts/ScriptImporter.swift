import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Reads a script out of a document: plain text, Markdown, rich text, Word,
/// web pages and PDFs. The prompter shows plain text, so formatting is
/// dropped and Markdown syntax removed; [brackets] stay, since they are
/// stage directions.
enum ScriptImporter {
    enum ImportError: LocalizedError {
        case unsupported(String)
        case empty(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name): return "\(name) is not a script file Lafz Prompter can read."
            case .empty(let name): return "\(name) has no text in it."
            case .unreadable(let name): return "\(name) could not be read."
            }
        }
    }

    static let fileExtensions = ["txt", "text", "md", "markdown", "rtf", "rtfd", "docx", "doc", "odt", "html", "htm", "pdf"]

    static var contentTypes: [UTType] {
        fileExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func canRead(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    /// The file's name without its extension, for the script's title.
    static func title(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func read(_ url: URL) throws -> String {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard canRead(url) else { throw ImportError.unsupported(name) }

        let raw: String
        switch ext {
        case "txt", "text":
            raw = try plainText(url)
        case "md", "markdown":
            raw = stripMarkdown(try plainText(url))
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw ImportError.unreadable(name) }
            raw = unwrapLines(document.string ?? "")
        default:
            raw = try richText(url, ext: ext)
        }
        let text = normalise(raw)
        guard !text.isEmpty else { throw ImportError.empty(name) }
        return text
    }

    private static func plainText(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        do { return try String(contentsOf: url, usedEncoding: &encoding) }
        catch { throw ImportError.unreadable(url.lastPathComponent) }
    }

    private static func richText(_ url: URL, ext: String) throws -> String {
        let types: [String: NSAttributedString.DocumentType] = [
            "rtf": .rtf, "rtfd": .rtfd, "docx": .officeOpenXML, "doc": .docFormat,
            "odt": .openDocument, "html": .html, "htm": .html,
        ]
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        if let type = types[ext] { options[.documentType] = type }
        do {
            return try NSAttributedString(url: url, options: options, documentAttributes: nil).string
        } catch {
            throw ImportError.unreadable(url.lastPathComponent)
        }
    }

    /// Unix line endings, no trailing spaces, at most one blank line in a row.
    static func normalise(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) {
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes the Markdown a reader should not say aloud: heading marks,
    /// list bullets, emphasis, link targets, code fences, rules and quotes.
    static func stripMarkdown(_ text: String) -> String {
        let rules: [(String, String)] = [
            (#"(?m)^\s*(```|~~~).*$"#, ""),             // code fences
            (#"(?m)^\s{0,3}([-*_]\s*){3,}$"#, ""),      // horizontal rules
            (#"(?m)^\s{0,3}#{1,6}\s+"#, ""),            // headings
            (#"(?m)^\s{0,3}>\s?"#, ""),                 // block quotes
            (#"(?m)^(\s*)[-*+]\s+"#, "$1"),             // bullets
            (#"!\[([^\]]*)\]\([^)]*\)"#, "$1"),         // images
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),          // links, keeping bare [stage directions]
            (#"(\*\*|__)(.+?)\1"#, "$2"),               // bold
            (#"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, "$1"), // italics
            (#"`([^`]+)`"#, "$1"),                      // inline code
        ]
        return rules.reduce(text) { text, rule in
            text.replacingOccurrences(of: rule.0, with: rule.1, options: .regularExpression)
        }
    }

    /// PDFs break every printed line. Joins lines inside a paragraph, keeping
    /// a break after a blank line or a line that ends a sentence, and mends
    /// words hyphenated across lines.
    static func unwrapLines(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if index > 0 {
                let previous = result.last
                if trimmed.isEmpty || previous == nil || previous == "\n" {
                    result += "\n"
                } else if let previous, ".!?:\"”".contains(previous) {
                    result += "\n"
                } else if previous == "-", result.dropLast().last?.isLetter == true {
                    result.removeLast()
                } else {
                    result += " "
                }
            }
            result += trimmed
        }
        return result
    }
}
