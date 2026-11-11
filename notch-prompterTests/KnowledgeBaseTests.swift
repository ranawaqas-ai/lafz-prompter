import Foundation
import Testing
@testable import LafzPrompter

struct KnowledgeBaseTests {
    /// A throwaway folder with the given files, removed when the test ends.
    private final class Fixture {
        let root: URL

        init(_ files: [String: Data]) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("kb-\(UUID().uuidString)", isDirectory: true)
            for (path, data) in files {
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
        }

        func git(_ args: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + args
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
        }

        func names(_ urls: [URL]) -> [String] {
            urls.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
        }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    private static let text = Data("hello".utf8)

    @Test func gitRepoFollowsRootAndNestedGitignore() throws {
        let fixture = try Fixture([
            ".gitignore": Data("secret.txt\nbuild/\n".utf8),
            "src/main.swift": Self.text,
            "src/.gitignore": Data("generated.swift\n".utf8),
            "src/generated.swift": Self.text,
            "secret.txt": Self.text,
            "build/out.txt": Self.text,
            "README.md": Self.text,
        ])
        try fixture.git("init", "-q")

        let files = fixture.names(try KnowledgeBase.files(in: fixture.root))
        #expect(files.sorted() == [".gitignore", "README.md", "src/.gitignore", "src/main.swift"])
    }

    @Test func plainFolderSkipsBuildAndDependencyDirectories() throws {
        let fixture = try Fixture([
            "notes.md": Self.text,
            "node_modules/pkg/index.js": Self.text,
            "build/out.txt": Self.text,
            ".git/config": Self.text,
            "docs/guide.txt": Self.text,
        ])

        let files = fixture.names(try KnowledgeBase.files(in: fixture.root))
        #expect(files == ["docs/guide.txt", "notes.md"])
    }

    @Test func binaryFilesAreLeftOutOfTheText() throws {
        let fixture = try Fixture([
            "a.txt": Data("alpha".utf8),
            "image.png": Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x1A]),
        ])

        let loaded = KnowledgeBase.load([fixture.root])
        #expect(loaded.sources.first?.fileCount == 1)
        #expect(loaded.text.contains("alpha"))
        #expect(loaded.text.contains("a.txt\">"))
        #expect(!loaded.text.contains("image.png"))
    }

    @Test func missingSourceReportsAnErrorInsteadOfFailing() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let loaded = KnowledgeBase.load([missing])
        #expect(loaded.sources.first?.error != nil)
        #expect(loaded.tokens == 0)
    }
}
