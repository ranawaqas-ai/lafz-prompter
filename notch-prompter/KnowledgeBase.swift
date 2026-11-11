import Foundation
import PDFKit

/// Turns the user's files and folders into the text sent with every question.
enum KnowledgeBase {
    struct Source: Equatable {
        let url: URL
        /// Tokens this source adds, estimated.
        let tokens: Int
        let fileCount: Int
        let error: String?
    }

    struct Loaded {
        let text: String
        let sources: [Source]
        var tokens: Int { sources.reduce(0) { $0 + $1.tokens } }
    }

    /// Directories never worth sending, used when a folder is not a git repo.
    static let skippedDirectories: Set<String> = [
        ".git", "node_modules", "build", ".build", "DerivedData", "Pods", "dist",
        ".next", "target", "vendor", "__pycache__", ".venv", "venv",
    ]

    /// About four characters per token for English and code; good enough to
    /// warn before a context window overflows.
    static func estimateTokens(_ text: String) -> Int { (text.count + 3) / 4 }

    static func load(_ urls: [URL]) -> Loaded {
        var text = ""
        var sources: [Source] = []
        for url in urls {
            let files: [URL]
            do {
                files = try self.files(in: url)
            } catch {
                sources.append(Source(url: url, tokens: 0, fileCount: 0, error: error.localizedDescription))
                continue
            }
            let base = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            var sourceText = ""
            var count = 0
            for file in files {
                guard let content = readText(file) else { continue }
                let path = file.path.replacingOccurrences(of: base.path + "/", with: "")
                let label = url.hasDirectoryPath ? "\(url.lastPathComponent)/\(path)" : path
                sourceText += "<file path=\"\(label)\">\n\(content)\n</file>\n"
                count += 1
            }
            text += sourceText
            sources.append(Source(url: url, tokens: estimateTokens(sourceText), fileCount: count, error: nil))
        }
        return Loaded(text: text, sources: sources)
    }

    /// The files a source stands for: itself, or the files inside a folder.
    static func files(in url: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ProviderError(message: "Not found")
        }
        guard isDirectory.boolValue else { return [url] }
        if let tracked = gitFiles(in: url) { return tracked }
        return walk(url)
    }

    /// Text of a file, or nil when it is binary or unreadable.
    static func readText(_ url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            return PDFDocument(url: url)?.string
        }
        guard let data = try? Data(contentsOf: url), !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Tracked and untracked-but-not-ignored files, so every .gitignore in the
    /// tree applies exactly as git reads it. Nil when the folder is not a repo.
    private static func gitFiles(in folder: URL) -> [URL]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "."]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data.split(separator: 0)
            .compactMap { String(data: Data($0), encoding: .utf8) }
            .map { folder.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path < $1.path }
    }

    /// Relative paths from the enumerator keep the folder's own prefix; the
    /// URL-based enumerator resolves /var to /private/var and breaks labels.
    private static func walk(_ folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(atPath: folder.path) else { return [] }
        var files: [URL] = []
        while let relative = enumerator.nextObject() as? String {
            let name = (relative as NSString).lastPathComponent
            let type = enumerator.fileAttributes?[.type] as? FileAttributeType
            if type == .typeDirectory {
                if name.hasPrefix(".") || skippedDirectories.contains(name) { enumerator.skipDescendants() }
            } else if type == .typeRegular, !name.hasPrefix(".") {
                files.append(folder.appendingPathComponent(relative))
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
