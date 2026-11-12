import Foundation

/// Turns a Fountain screenplay (fountain.io) into a prompter script. Only
/// dialogue is read aloud. Speaker names, parentheticals and notes become
/// [cues]; scene headings, action, transitions and the title page are
/// dropped. A file with no dialogue is narration, so its action is kept.
enum Fountain {
    static func script(from source: String) -> String {
        let elements = parse(source)
        let speakers = Set(elements.compactMap { if case .speaker(let name) = $0 { person(name) } else { nil } })
        let hasDialogue = elements.contains { if case .dialogue = $0 { true } else { false } }

        var blocks: [[String]] = []
        var lastSpeaker: String?
        for element in elements {
            switch element {
            case .speaker(let name):
                blocks.append(speakers.count > 1 && person(name) != lastSpeaker ? ["[\(name)]"] : [])
                lastSpeaker = person(name)
            case .parenthetical(let text):
                appendLine("[\(text)]", to: &blocks)
            case .dialogue(let text):
                appendLine(text, to: &blocks)
            case .note(let text):
                blocks.append(["[\(text)]"])
            case .action(let text) where !hasDialogue:
                blocks.append([text])
            case .sceneBreak:
                lastSpeaker = nil
            case .action:
                break
            }
        }
        return blocks.filter { !$0.isEmpty }.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    /// The speaker without an extension, so WAQAS (CONT'D) is still WAQAS.
    private static func person(_ name: String) -> String {
        name.split(separator: "(", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
    }

    private static func appendLine(_ line: String, to blocks: inout [[String]]) {
        if blocks.isEmpty { blocks.append([]) }
        blocks[blocks.count - 1].append(line)
    }

    enum Element: Equatable {
        case speaker(String)
        case parenthetical(String)
        case dialogue(String)
        case note(String)
        case action(String)
        case sceneBreak
    }

    static func parse(_ source: String) -> [Element] {
        let lines = withoutTitlePage(cleaned(source)).components(separatedBy: "\n")
        var elements: [Element] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let blankBefore = index == 0 || lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty
            let next = index + 1 < lines.count ? lines[index + 1].trimmingCharacters(in: .whitespaces) : ""
            index += 1

            if trimmed.isEmpty || isSection(trimmed) || isSynopsis(trimmed) || isPageBreak(trimmed) { continue }
            if let note = wholeNote(trimmed) { elements.append(.note(note)); continue }
            if blankBefore, isSceneHeading(trimmed) || isTransition(trimmed, blankAfter: next.isEmpty) {
                elements.append(.sceneBreak)
                continue
            }
            if blankBefore, !next.isEmpty, let name = speakerName(trimmed) {
                elements.append(.speaker(name))
                while index < lines.count {
                    let spoken = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !spoken.isEmpty else { break }
                    index += 1
                    if spoken.hasPrefix("("), spoken.hasSuffix(")") {
                        elements.append(.parenthetical(String(spoken.dropFirst().dropLast())))
                    } else {
                        elements.append(.dialogue(plain(spoken.hasPrefix("~") ? String(spoken.dropFirst()) : spoken)))
                    }
                }
                continue
            }
            elements.append(.action(plain(actionText(trimmed))))
        }
        return elements
    }

    // MARK: Line kinds

    private static func isSection(_ line: String) -> Bool { line.hasPrefix("#") }
    private static func isSynopsis(_ line: String) -> Bool { line.hasPrefix("=") && !isPageBreak(line) }
    private static func isPageBreak(_ line: String) -> Bool { line.count >= 3 && line.allSatisfy { $0 == "=" } }

    private static func isSceneHeading(_ line: String) -> Bool {
        if line.hasPrefix(".") { return !line.hasPrefix("..") }
        return line.range(of: #"^(INT|EXT|EST|INT\.?/EXT|I/E)[\. ]"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isTransition(_ line: String, blankAfter: Bool) -> Bool {
        if line.hasPrefix(">") { return !line.hasSuffix("<") }
        return blankAfter && line.hasSuffix("TO:") && line == line.uppercased()
    }

    /// The character's name, from a line in capitals or one forced with @.
    /// Extensions like (V.O.) stay; the dual-dialogue mark ^ goes.
    private static func speakerName(_ line: String) -> String? {
        let name = line.hasSuffix("^") ? String(line.dropLast()).trimmingCharacters(in: .whitespaces) : line
        if name.hasPrefix("@") { return String(name.dropFirst()) }
        if name.hasPrefix("!") { return nil }
        let beforeExtension = name.split(separator: "(", maxSplits: 1).first.map(String.init) ?? name
        guard beforeExtension.contains(where: \.isLetter),
              beforeExtension == beforeExtension.uppercased() else { return nil }
        return name
    }

    /// A line that is nothing but a [[note]] (already shortened to [note]).
    private static func wholeNote(_ line: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]"), !line.dropFirst().contains("[") else { return nil }
        return String(line.dropFirst().dropLast())
    }

    private static func actionText(_ line: String) -> String {
        var text = line
        if text.hasPrefix("!") { text.removeFirst() }
        if text.hasPrefix(">"), text.hasSuffix("<") { text = String(text.dropFirst().dropLast()) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Text clean-up

    /// Unix line endings, no /* boneyard */, and [[notes]] as [cues].
    private static func cleaned(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)\[\[\s*(.*?)\s*\]\]"#, with: "[$1]", options: .regularExpression)
    }

    /// The title page is `Key: value` lines (with indented continuations)
    /// up to the first blank line, and only at the very top.
    private static func withoutTitlePage(_ text: String) -> String {
        let trimmed = text.drop { $0 == "\n" }
        guard trimmed.range(of: #"^[A-Za-z][A-Za-z ]*:"#, options: .regularExpression) != nil else { return text }
        guard let end = trimmed.range(of: "\n\n") else { return "" }
        return String(trimmed[end.upperBound...])
    }

    /// Drops *emphasis*, **bold**, _underline_ marks and \escapes.
    private static func plain(_ text: String) -> String {
        let rules: [(String, String)] = [
            (#"(?<!\\)\*{1,3}(?=\S)(.+?)(?<=\S)(?<!\\)\*{1,3}"#, "$1"),
            (#"(?<!\\)_(?=\S)(.+?)(?<=\S)(?<!\\)_"#, "$1"),
            (#"\\([*_\\])"#, "$1"),
        ]
        return rules.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1, options: .regularExpression) }
    }
}
