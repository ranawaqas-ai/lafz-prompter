import SwiftUI

/// Splits an answer into prose and fenced code blocks. Works on a partial,
/// still-streaming answer: an unclosed fence is a code block in progress.
enum AnswerFormatting {
    enum Segment: Equatable {
        case prose(String)
        case code(language: String?, code: String)
    }

    /// Appended to the user's instructions so code arrives in a form the
    /// prompter can format and colour.
    static let formattingRule = """
    When the answer includes code, put it in a fenced code block that names the language, \
    for example ```python. Keep the code short and readable on a narrow screen.
    """

    static func segments(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var language: String?
        var inCode = false

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { segments.append(.prose(joined)) }
            prose = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    segments.append(.code(language: language, code: code.joined(separator: "\n")))
                    code = []
                } else {
                    flushProse()
                    let tag = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                    language = tag.isEmpty ? nil : tag
                }
                inCode.toggle()
            } else if inCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        if inCode {
            segments.append(.code(language: language, code: code.joined(separator: "\n")))
        } else {
            flushProse()
        }
        return segments
    }
}

/// Colours code with a small tokenizer: comments, strings, numbers, keywords,
/// type names and function calls, for the languages interviews use most.
/// Unknown languages get a common keyword set.
enum SyntaxHighlighter {
    enum Token: CaseIterable {
        case comment, string, number, keyword, type, function
    }

    static func highlight(_ code: String, language: String?, dark: Bool) -> AttributedString {
        var result = AttributedString(code)
        for (range, token) in tokens(in: code, language: language) {
            guard let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[start..<end].foregroundColor = color(token, dark: dark)
        }
        return result
    }

    /// Non-overlapping token ranges. Comments and strings are found first so
    /// a keyword inside a string or comment is not coloured as a keyword.
    static func tokens(in code: String, language: String?) -> [(Range<String.Index>, Token)] {
        let spec = LanguageSpec.for(language)
        var taken: [Range<String.Index>] = []
        var found: [(Range<String.Index>, Token)] = []

        func scan(_ pattern: String, _ token: Token, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let range = Range(match.range, in: code),
                      !taken.contains(where: { $0.overlaps(range) }) else { continue }
                taken.append(range)
                found.append((range, token))
            }
        }

        // Block comments and strings can span lines, so they run first and
        // in source order of precedence.
        for pattern in spec.commentPatterns { scan(pattern, .comment, options: [.anchorsMatchLines]) }
        scan(#""""[\s\S]*?"""|'''[\s\S]*?'''"#, .string)
        scan(#""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#, .string)
        if spec.backtickStrings { scan(#"`(?:\\.|[^`\\])*`"#, .string) }
        scan(#"\b(?:0x[0-9A-Fa-f_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number)
        if !spec.keywords.isEmpty {
            let words = spec.keywords.sorted { $0.count > $1.count }.joined(separator: "|")
            scan("\\b(?:\(words))\\b", .keyword, options: spec.caseInsensitive ? [.caseInsensitive] : [])
        }
        scan(#"\b[A-Z][A-Za-z0-9_]*\b"#, .type)
        scan(#"\b[a-z_][A-Za-z0-9_]*(?=\s*\()"#, .function)
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }
    }

    private static func color(_ token: Token, dark: Bool) -> Color {
        // Close to Xcode's default themes, which most people can read at a glance.
        switch (token, dark) {
        case (.comment, true): return Color(red: 0.50, green: 0.55, blue: 0.60)
        case (.comment, false): return Color(red: 0.36, green: 0.42, blue: 0.47)
        case (.string, true): return Color(red: 0.99, green: 0.42, blue: 0.36)
        case (.string, false): return Color(red: 0.77, green: 0.10, blue: 0.09)
        case (.number, true): return Color(red: 0.82, green: 0.75, blue: 0.41)
        case (.number, false): return Color(red: 0.11, green: 0.00, blue: 0.81)
        case (.keyword, true): return Color(red: 0.99, green: 0.37, blue: 0.64)
        case (.keyword, false): return Color(red: 0.61, green: 0.14, blue: 0.58)
        case (.type, true): return Color(red: 0.36, green: 0.85, blue: 1.00)
        case (.type, false): return Color(red: 0.04, green: 0.31, blue: 0.47)
        case (.function, true): return Color(red: 0.40, green: 0.72, blue: 0.86)
        case (.function, false): return Color(red: 0.20, green: 0.43, blue: 0.48)
        }
    }
}

private struct LanguageSpec {
    var keywords: Set<String>
    var commentPatterns: [String]
    var backtickStrings = false
    var caseInsensitive = false

    private static let slashComments = [#"/\*[\s\S]*?\*/"#, #"//.*$"#]
    private static let hashComments = [#"#.*$"#]

    static func `for`(_ language: String?) -> LanguageSpec {
        switch language ?? "" {
        case "swift":
            return LanguageSpec(keywords: ["func", "let", "var", "if", "else", "guard", "return", "for", "in", "while", "switch", "case", "default", "struct", "class", "enum", "protocol", "extension", "import", "self", "Self", "nil", "true", "false", "try", "throw", "throws", "async", "await", "init", "private", "public", "internal", "static", "final", "where", "some", "any", "inout", "defer", "break", "continue", "actor", "mutating", "override", "do", "catch", "as", "is"], commentPatterns: slashComments)
        case "python", "py":
            return LanguageSpec(keywords: ["def", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is", "None", "True", "False", "class", "import", "from", "as", "with", "try", "except", "finally", "raise", "lambda", "yield", "pass", "break", "continue", "global", "nonlocal", "async", "await", "self", "assert", "del"], commentPatterns: hashComments)
        case "javascript", "js", "typescript", "ts", "jsx", "tsx":
            return LanguageSpec(keywords: ["function", "const", "let", "var", "if", "else", "return", "for", "while", "of", "in", "new", "class", "extends", "import", "from", "export", "default", "async", "await", "try", "catch", "finally", "throw", "null", "undefined", "true", "false", "this", "typeof", "instanceof", "switch", "case", "break", "continue", "interface", "type", "enum", "implements", "public", "private", "readonly", "as", "yield"], commentPatterns: slashComments, backtickStrings: true)
        case "java", "kotlin", "kt", "csharp", "cs", "c#":
            return LanguageSpec(keywords: ["public", "private", "protected", "static", "final", "class", "interface", "enum", "extends", "implements", "new", "return", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "try", "catch", "finally", "throw", "throws", "void", "int", "long", "double", "float", "boolean", "bool", "char", "byte", "short", "null", "true", "false", "this", "super", "import", "package", "var", "val", "fun", "using", "namespace", "string", "override", "async", "await", "when", "object"], commentPatterns: slashComments)
        case "go", "golang":
            return LanguageSpec(keywords: ["func", "package", "import", "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "return", "if", "else", "for", "range", "switch", "case", "default", "break", "continue", "select", "nil", "true", "false", "make", "new", "len", "append", "error", "string", "int", "bool"], commentPatterns: slashComments, backtickStrings: true)
        case "rust", "rs":
            return LanguageSpec(keywords: ["fn", "let", "mut", "if", "else", "match", "for", "in", "while", "loop", "return", "struct", "enum", "impl", "trait", "pub", "use", "mod", "self", "Self", "true", "false", "as", "ref", "move", "async", "await", "where", "const", "static", "dyn", "break", "continue", "crate", "unsafe"], commentPatterns: slashComments)
        case "c", "cpp", "c++", "h", "hpp", "objc", "objective-c":
            return LanguageSpec(keywords: ["int", "long", "short", "char", "float", "double", "void", "bool", "unsigned", "signed", "const", "static", "struct", "union", "enum", "typedef", "return", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "sizeof", "class", "public", "private", "protected", "virtual", "template", "typename", "namespace", "using", "new", "delete", "nullptr", "true", "false", "auto", "this", "include", "define"], commentPatterns: slashComments)
        case "sql", "postgres", "postgresql", "mysql", "sqlite":
            return LanguageSpec(keywords: ["select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create", "table", "index", "on", "join", "left", "right", "inner", "outer", "group", "by", "order", "having", "limit", "offset", "as", "distinct", "count", "sum", "avg", "min", "max", "null", "is", "in", "exists", "primary", "key", "foreign", "references", "with", "union", "all", "case", "when", "then", "else", "end", "desc", "asc", "begin", "commit", "transaction"], commentPatterns: [#"--.*$"#, #"/\*[\s\S]*?\*/"#], caseInsensitive: true)
        case "bash", "sh", "shell", "zsh", "console":
            return LanguageSpec(keywords: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "case", "esac", "function", "return", "export", "local", "echo", "exit", "set", "unset", "source", "sudo", "cd"], commentPatterns: hashComments)
        case "ruby", "rb":
            return LanguageSpec(keywords: ["def", "end", "if", "elsif", "else", "unless", "while", "until", "for", "in", "do", "return", "class", "module", "require", "self", "nil", "true", "false", "yield", "begin", "rescue", "ensure", "raise", "attr_accessor", "puts"], commentPatterns: hashComments)
        case "json", "yaml", "yml", "text", "txt", "plaintext":
            return LanguageSpec(keywords: ["true", "false", "null"], commentPatterns: language == "yaml" || language == "yml" ? hashComments : [])
        default:
            return LanguageSpec(keywords: ["if", "else", "for", "while", "return", "function", "func", "def", "class", "struct", "let", "var", "const", "import", "true", "false", "null", "nil", "None", "new", "try", "catch", "switch", "case", "break", "continue"], commentPatterns: slashComments + hashComments)
        }
    }
}
