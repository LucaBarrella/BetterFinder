import Foundation
import AppKit

@MainActor
struct SyntaxHighlighter {

    // MARK: - Public API

    static func highlight(_ text: String, forExtension ext: String) -> NSAttributedString {
        let normalized = ext.lowercased().replacingOccurrences(of: ".", with: "")
        guard let rules = rulesByExtension[normalized] else {
            return NSAttributedString(
                string: text,
                attributes: [.foregroundColor: NSColor.labelColor, .font: font()]
            )
        }

        let attr = NSMutableAttributedString(
            string: text,
            attributes: [.foregroundColor: NSColor.labelColor, .font: font()]
        )
        let full = NSRange(location: 0, length: (text as NSString).length)

        for rule in rules {
            let color = rule.color()
            let isItalic = rule.isItalic
            rule.regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match = match else { return }
                for i in 1 ..< match.numberOfRanges {
                    let r = match.range(at: i)
                    if r.location != NSNotFound {
                        attr.addAttribute(.foregroundColor, value: color, range: r)
                        if isItalic {
                            attr.addAttribute(.font, value: font(italic: true), range: r)
                        }
                    }
                }
            }
        }

        return attr
    }

    static func isSupportedExtension(_ ext: String) -> Bool {
        let normalized = ext.lowercased().replacingOccurrences(of: ".", with: "")
        return rulesByExtension[normalized] != nil || extensionOverrides.contains(normalized)
    }

    // MARK: - Internal Types

    struct LanguageRule {
        let regex: NSRegularExpression
        let color: () -> NSColor
        let isItalic: Bool
    }

    // MARK: - Font

    private static func font(italic: Bool = false) -> NSFont {
        let descriptor = NSFont.systemFont(ofSize: 11.5).fontDescriptor
        if italic {
            let italicDesc = descriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: italicDesc, size: 11.5) ?? NSFont.systemFont(ofSize: 11.5)
        }
        return NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    }

    // MARK: - Color Helpers

    private static var keywordColor: NSColor { .systemPurple }
    private static var stringColor: NSColor { .systemRed }
    private static var commentColor: NSColor { .systemGray }
    private static var numberColor: NSColor { .systemBlue }
    private static var typeColor: NSColor { .systemTeal }
    private static var functionColor: NSColor { .systemBrown }

    // MARK: - Regex Helpers

    private static func re(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private static func kw(_ words: [String]) -> String {
        let joined = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return "\\b(\(joined))\\b"
    }

    private static func kw(_ words: String...) -> String {
        kw(words)
    }

    private static func comment(_ single: String? = nil, blockOpen: String? = nil, blockClose: String? = nil) -> [LanguageRule] {
        var rules: [LanguageRule] = []
        if let single = single {
            rules.append(LanguageRule(
                regex: re("\(NSRegularExpression.escapedPattern(for: single)).*"),
                color: { commentColor },
                isItalic: true
            ))
        }
        if let open = blockOpen, let close = blockClose {
            let pattern = "\(NSRegularExpression.escapedPattern(for: open))(.*?)\(NSRegularExpression.escapedPattern(for: close))"
            rules.append(LanguageRule(
                regex: re(pattern),
                color: { commentColor },
                isItalic: true
            ))
        }
        return rules
    }

    private static func stringRules() -> [LanguageRule] {
        // Single-quoted, double-quoted, template/backtick
        [
            LanguageRule(regex: re("(\"(?:[^\"\\\\]|\\\\.)*\")"), color: { stringColor }, isItalic: false),
            LanguageRule(regex: re("('(?:[^'\\\\]|\\\\.)*')"), color: { stringColor }, isItalic: false),
            LanguageRule(regex: re("(`(?:[^`\\\\]|\\\\.)*`)"), color: { stringColor }, isItalic: false),
        ]
    }

    private static func numberRule() -> LanguageRule {
        LanguageRule(
            regex: re("\\b(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|[0-9][0-9_]*\\.?[0-9_]*([eE][+-]?[0-9_]+)?f?d?)\\b"),
            color: { numberColor },
            isItalic: false
        )
    }

    private static func keywordRule(_ words: String...) -> LanguageRule {
        LanguageRule(regex: re(kw(words)), color: { keywordColor }, isItalic: false)
    }

    private static func typeRule() -> LanguageRule {
        // PascalCase tokens
        LanguageRule(
            regex: re("\\b([A-Z][a-zA-Z0-9]{1,})\\b"),
            color: { typeColor },
            isItalic: false
        )
    }

    private static func functionRule() -> LanguageRule {
        LanguageRule(
            regex: re("\\b([a-zA-Z_][a-zA-Z0-9_]*)(?=\\s*\\()"),
            color: { functionColor },
            isItalic: false
        )
    }

    // MARK: - Language Rules

    // swiftlint:disable:next cyclomatic_complexity
    private static func buildRules(for language: String) -> [LanguageRule] {
        switch language {
        // Swift
        case "swift":
            return comment(nil, blockOpen: "/*", blockClose: "*/") +
                [LanguageRule(regex: re("(//.*)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    numberRule(),
                    keywordRule(
                        "func", "var", "let", "class", "struct", "enum", "protocol", "extension",
                        "import", "return", "if", "else", "guard", "switch", "case", "default",
                        "for", "in", "while", "repeat", "break", "continue", "throw", "throws",
                        "try", "catch", "do", "defer", "as", "is", "nil", "self", "Self",
                        "true", "false", "init", "deinit", "subscript", "static", "private",
                        "public", "internal", "open", "fileprivate", "weak", "unowned",
                        "mutating", "nonmutating", "optional", "required", "lazy",
                        "async", "await", "actor", "some", "any", "get", "set",
                        "willSet", "didSet", "where", "typealias", "associatedtype",
                        "precedencegroup", "infix", "prefix", "postfix", "indirect"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // Python
        case "python":
            return [LanguageRule(regex: re("(#.*$)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    numberRule(),
                    keywordRule(
                        "def", "class", "import", "from", "return", "if", "elif", "else",
                        "for", "in", "while", "break", "continue", "pass", "raise",
                        "try", "except", "finally", "with", "as", "yield", "lambda",
                        "and", "or", "not", "is", "True", "False", "None", "global",
                        "nonlocal", "assert", "del", "async", "await", "match", "case",
                        "print"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // JavaScript / TypeScript
        case "javascript", "typescript":
            return comment(nil, blockOpen: "/*", blockClose: "*/") +
                [LanguageRule(regex: re("(//.*)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    numberRule(),
                    keywordRule(
                        "const", "let", "var", "function", "return", "if", "else", "for",
                        "while", "do", "switch", "case", "default", "break", "continue",
                        "throw", "try", "catch", "finally", "new", "delete", "typeof",
                        "instanceof", "void", "this", "class", "extends", "super",
                        "import", "export", "from", "as", "async", "await", "yield",
                        "of", "in", "with", "debugger", "true", "false", "null", "undefined",
                        // TypeScript extras
                        "type", "interface", "enum", "namespace", "declare", "abstract",
                        "implements", "readonly", "keyof", "infer", "never", "unknown",
                        "module", "require", "private", "public", "protected", "override",
                        "satisfies", "as", "is"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // Rust
        case "rust":
            return [LanguageRule(regex: re("(//.*$)"), color: { commentColor }, isItalic: true)] +
                comment(nil, blockOpen: "/*", blockClose: "*/") +
                stringRules() + [
                    numberRule(),
                    keywordRule(
                        "fn", "let", "mut", "const", "static", "struct", "enum", "trait",
                        "impl", "type", "mod", "pub", "use", "crate", "super", "self",
                        "Self", "if", "else", "match", "for", "in", "while", "loop",
                        "break", "continue", "return", "as", "ref", "move", "async",
                        "await", "dyn", "where", "unsafe", "extern", "true", "false",
                        "macro_rules"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // Go
        case "go":
            return comment(nil, blockOpen: "/*", blockClose: "*/") +
                [LanguageRule(regex: re("(//.*)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    numberRule(),
                    keywordRule(
                        "func", "var", "const", "type", "struct", "interface", "map",
                        "package", "import", "return", "if", "else", "for", "range",
                        "switch", "case", "default", "break", "continue", "go",
                        "defer", "select", "chan", "fallthrough", "goto", "nil",
                        "true", "false", "iota", "make", "new", "append", "delete",
                        "len", "cap", "copy", "close", "panic", "recover", "print", "println"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // C / C++ / ObjC
        case "c", "cpp":
            return comment(nil, blockOpen: "/*", blockClose: "*/") +
                [LanguageRule(regex: re("(//.*)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    // Preprocessor directives
                    LanguageRule(
                        regex: re("(#[a-zA-Z_]+.*)"),
                        color: { keywordColor },
                        isItalic: false
                    ),
                    numberRule(),
                    keywordRule(
                        "if", "else", "for", "while", "do", "switch", "case", "default",
                        "break", "continue", "return", "goto", "sizeof", "typedef",
                        "struct", "union", "enum", "class", "const", "static", "extern",
                        "volatile", "register", "signed", "unsigned", "void", "int",
                        "char", "short", "long", "float", "double", "auto", "inline",
                        "restrict", "bool", "true", "false", "NULL", "nullptr",
                        "template", "typename", "namespace", "using", "virtual",
                        "override", "final", "new", "delete", "public", "private",
                        "protected", "friend", "operator", "this", "throw", "try",
                        "catch", "noexcept", "constexpr", "decltype", "auto",
                        "static_cast", "dynamic_cast", "const_cast", "reinterpret_cast",
                        "explicit", "mutable", "thread_local",
                        // ObjC
                        "@interface", "@implementation", "@protocol", "@end",
                        "@property", "@synthesize", "@dynamic", "@selector",
                        "@encode", "@synchronized", "@autoreleasepool", "@try",
                        "@catch", "@finally", "@throw", "@optional", "@required",
                        "id", "nil", "YES", "NO", "self", "super"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // Shell
        case "shell":
            return [LanguageRule(regex: re("(#.*$)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    numberRule(),
                    keywordRule(
                        "if", "then", "else", "elif", "fi", "for", "in", "do", "done",
                        "while", "until", "case", "esac", "function", "return", "exit",
                        "export", "source", "local", "readonly", "declare", "unset",
                        "shift", "set", "eval", "exec", "trap", "true", "false",
                        "select", "time"
                    ),
                    // Built-in commands
                    LanguageRule(
                        regex: re(kw(
                            "echo", "printf", "read", "test", "cd", "pwd", "pushd", "popd",
                            "ls", "cat", "grep", "sed", "awk", "find", "mkdir", "rmdir",
                            "rm", "cp", "mv", "ln", "chmod", "chown", "kill", "ps",
                            "wait", "sleep", "curl", "wget"
                        )),
                        color: { functionColor },
                        isItalic: false
                    ),
                ]

        // Ruby
        case "ruby":
            return [LanguageRule(regex: re("(#.*$)"), color: { commentColor }, isItalic: true)] +
                comment(nil, blockOpen: "=begin", blockClose: "=end") +
                stringRules() + [
                    // Symbol
                    LanguageRule(regex: re("(\\:[a-zA-Z_][a-zA-Z0-9_?!]*\\b)"), color: { numberColor }, isItalic: false),
                    numberRule(),
                    keywordRule(
                        "def", "end", "class", "module", "if", "elsif", "else", "unless",
                        "case", "when", "while", "until", "for", "in", "do", "begin",
                        "rescue", "ensure", "raise", "return", "yield", "break", "next",
                        "redo", "retry", "super", "self", "nil", "true", "false", "and",
                        "or", "not", "alias", "defined?", "undef", "then", "puts",
                        "require", "include", "extend", "attr_accessor", "attr_reader",
                        "attr_writer", "initialize", "lambda", "proc"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // Java / Kotlin
        case "java", "kotlin":
            return comment(nil, blockOpen: "/*", blockClose: "*/") +
                [LanguageRule(regex: re("(//.*)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    numberRule(),
                    keywordRule(
                        "public", "private", "protected", "class", "interface", "enum",
                        "extends", "implements", "static", "final", "abstract",
                        "new", "return", "if", "else", "for", "while", "do", "switch",
                        "case", "default", "break", "continue", "throw", "throws",
                        "try", "catch", "finally", "import", "package", "void",
                        "int", "long", "short", "byte", "float", "double", "boolean",
                        "char", "String", "null", "true", "false", "instanceof",
                        "this", "super", "synchronized", "volatile", "transient",
                        "native", "strictfp", "assert", "goto", "const",
                        // Kotlin extras
                        "val", "var", "fun", "when", "data", "sealed", "object",
                        "companion", "init", "constructor", "override", "open",
                        "inner", "lateinit", "suspend", "inline", "reified",
                        "tailrec", "operator", "infix", "is", "as", "by",
                        "lazy", "it", "Unit", "Nothing", "Any", "typealias",
                        "expect", "actual", "value", "annotation"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // JSON
        case "json":
            return stringRules() + [
                numberRule(),
                // JSON keywords
                LanguageRule(
                    regex: re(kw("true", "false", "null")),
                    color: { keywordColor },
                    isItalic: false
                ),
                // JSON keys (quoted strings followed by colon)
                LanguageRule(
                    regex: re("(\"(?:[^\"\\\\]|\\\\.)*\")(?=\\s*:)"),
                    color: { functionColor },
                    isItalic: false
                ),
            ]

        // YAML
        case "yaml":
            return [LanguageRule(regex: re("(#.*$)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    // YAML keys
                    LanguageRule(
                        regex: re("^([a-zA-Z_][a-zA-Z0-9_.-]*)(?=\\s*:)", multiline: true),
                        color: { functionColor },
                        isItalic: false
                    ),
                    numberRule(),
                    LanguageRule(
                        regex: re(kw("true", "false", "null", "yes", "no", "on", "off")),
                        color: { keywordColor },
                        isItalic: false
                    ),
                ]

        // XML / HTML
        case "xml", "html":
            // Block-style comments <!-- ... -->
            return comment(nil, blockOpen: "<!--", blockClose: "-->") +
                stringRules() + [
                    // Tags: <tagname and </tagname
                    LanguageRule(
                        regex: re("(</?\\w[\\w-]*)"),
                        color: { keywordColor },
                        isItalic: false
                    ),
                    // Attribute names
                    LanguageRule(
                        regex: re("\\s([a-zA-Z_:][a-zA-Z0-9_:.-]*)(=)"),
                        color: { functionColor },
                        isItalic: false
                    ),
                    // Closing brackets
                    LanguageRule(
                        regex: re("([/>])"),
                        color: { keywordColor },
                        isItalic: false
                    ),
                ]

        // CSS / SCSS / SASS / LESS
        case "css", "scss", "sass", "less":
            var rules = comment(nil, blockOpen: "/*", blockClose: "*/")
            if language == "scss" || language == "sass" || language == "less" {
                rules += [LanguageRule(regex: re("(//.*)"), color: { commentColor }, isItalic: true)]
            }
            return rules + stringRules() + [
                numberRule(),
                // CSS properties
                LanguageRule(
                    regex: re("([a-zA-Z-]+)(?=\\s*:)"),
                    color: { functionColor },
                    isItalic: false
                ),
                // CSS values (keywords)
                LanguageRule(
                    regex: re(kw(
                        "none", "auto", "inherit", "initial", "unset", "important",
                        "block", "inline", "inline-block", "flex", "grid", "table",
                        "relative", "absolute", "fixed", "sticky", "static",
                        "solid", "dashed", "dotted", "double", "groove", "ridge",
                        "hidden", "visible", "scroll", "overlay", "auto",
                        "ease", "linear", "ease-in", "ease-out", "ease-in-out",
                        "normal", "bold", "italic", "oblique", "underline", "overline",
                        "uppercase", "lowercase", "capitalize", "nowrap", "wrap",
                        "row", "column", "center", "stretch", "baseline", "start", "end",
                        "sans-serif", "serif", "monospace"
                    )),
                    color: { keywordColor },
                    isItalic: false
                ),
                // Selectors (.class and #id)
                LanguageRule(
                    regex: re("(\\.[a-zA-Z_][\\w-]*)"),
                    color: { typeColor },
                    isItalic: false
                ),
                LanguageRule(
                    regex: re("(#[a-zA-Z_][\\w-]*)"),
                    color: { numberColor },
                    isItalic: false
                ),
                // At-rules (@media, @keyframes, etc.)
                LanguageRule(
                    regex: re("(@[a-zA-Z-]+)"),
                    color: { keywordColor },
                    isItalic: false
                ),
            ]

        // SQL
        case "sql":
            return comment(nil, blockOpen: "/*", blockClose: "*/") +
                [LanguageRule(regex: re("(--.*$)"), color: { commentColor }, isItalic: true)] +
                stringRules() + [
                    numberRule(),
                    keywordRule(
                        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE",
                        "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX",
                        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "ON",
                        "AS", "AND", "OR", "NOT", "IN", "BETWEEN", "LIKE", "IS",
                        "NULL", "TRUE", "FALSE", "ORDER", "BY", "GROUP", "HAVING",
                        "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "COUNT",
                        "SUM", "AVG", "MIN", "MAX", "CASE", "WHEN", "THEN", "ELSE",
                        "END", "EXISTS", "UNIQUE", "PRIMARY", "KEY", "FOREIGN",
                        "REFERENCES", "CONSTRAINT", "DEFAULT", "AUTO_INCREMENT",
                        "CASCADE", "RESTRICT", "ADD", "COLUMN", "DATABASE", "SCHEMA",
                        "GRANT", "REVOKE", "COMMIT", "ROLLBACK", "TRANSACTION",
                        "BEGIN", "EXPLAIN", "DESCRIBE", "SHOW", "USE", "IF",
                        "DECLARE", "CURSOR", "FETCH", "OPEN", "CLOSE", "EXEC",
                        "PROCEDURE", "FUNCTION", "TRIGGER", "VIEW", "WITH",
                        "RECURSIVE", "WINDOW", "PARTITION", "OVER", "ROW",
                        "ROWS", "RANGE", "PRECEDING", "FOLLOWING", "UNBOUNDED",
                        "COALESCE", "NULLIF", "CAST", "CONVERT"
                    ),
                    typeRule(),
                    functionRule(),
                ]

        // Markdown
        case "markdown":
            return [
                // Headers
                LanguageRule(
                    regex: re("^(#{1,6}\\s.*)"),
                    color: { keywordColor },
                    isItalic: false
                ),
                // Bold
                LanguageRule(
                    regex: re("(\\*\\*(.+?)\\*\\*)"),
                    color: { typeColor },
                    isItalic: false
                ),
                // Italic
                LanguageRule(
                    regex: re("(\\*(.+?)\\*)"),
                    color: { functionColor },
                    isItalic: true
                ),
                // Inline code
                LanguageRule(
                    regex: re("(`[^`]+`)"),
                    color: { numberColor },
                    isItalic: false
                ),
                // Code blocks
                LanguageRule(
                    regex: re("(```[\\s\\S]*?```)"),
                    color: { numberColor },
                    isItalic: false
                ),
                // Links
                LanguageRule(
                    regex: re("(\\[.*?\\]\\(.*?\\))"),
                    color: { typeColor },
                    isItalic: false
                ),
                // Blockquotes
                LanguageRule(
                    regex: re("^(>.*)"),
                    color: { commentColor },
                    isItalic: true
                ),
                // List markers
                LanguageRule(
                    regex: re("^([\\s]*[-*+]\\s|\\d+\\.\\s)"),
                    color: { keywordColor },
                    isItalic: false
                ),
            ]

        default:
            return []
        }
    }

    // MARK: - Static Rules Registry

    private static let extensionOverrides: Set<String> = [
        "makefile", "dockerfile", "procfile", "gemfile", "rakefile",
        "guardfile", "podfile", "fastfile", "appfile", "matchfile"
    ]

    private static func re(_ pattern: String, multiline: Bool) -> NSRegularExpression {
        var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
        if multiline {
            options.insert(.anchorsMatchLines)
        }
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let rulesByExtension: [String: [LanguageRule]] = {
        var map: [String: [LanguageRule]] = [:]

        let swiftRules = buildRules(for: "swift")
        map["swift"] = swiftRules

        let pythonRules = buildRules(for: "python")
        map["py"] = pythonRules
        map["pyw"] = pythonRules

        let jsRules = buildRules(for: "javascript")
        map["js"] = jsRules
        map["jsx"] = jsRules
        map["mjs"] = jsRules
        map["cjs"] = jsRules

        let tsRules = buildRules(for: "typescript")
        map["ts"] = tsRules
        map["tsx"] = tsRules
        map["mts"] = tsRules
        map["cts"] = tsRules

        let rustRules = buildRules(for: "rust")
        map["rs"] = rustRules

        let goRules = buildRules(for: "go")
        map["go"] = goRules

        let cRules = buildRules(for: "c")
        map["c"] = cRules
        map["h"] = cRules
        map["m"] = cRules

        let cppRules = buildRules(for: "cpp")
        map["cpp"] = cppRules
        map["cc"] = cppRules
        map["cxx"] = cppRules
        map["hpp"] = cppRules
        map["hh"] = cppRules
        map["hxx"] = cppRules
        map["mm"] = cppRules

        let shellRules = buildRules(for: "shell")
        map["sh"] = shellRules
        map["bash"] = shellRules
        map["zsh"] = shellRules
        map["fish"] = shellRules

        let rubyRules = buildRules(for: "ruby")
        map["rb"] = rubyRules
        map["rake"] = rubyRules
        map["gemspec"] = rubyRules

        let javaRules = buildRules(for: "java")
        map["java"] = javaRules

        let kotlinRules = buildRules(for: "kotlin")
        map["kt"] = kotlinRules
        map["kts"] = kotlinRules

        let jsonRules = buildRules(for: "json")
        map["json"] = jsonRules
        map["jsonc"] = jsonRules

        let yamlRules = buildRules(for: "yaml")
        map["yaml"] = yamlRules
        map["yml"] = yamlRules

        let xmlRules = buildRules(for: "xml")
        map["xml"] = xmlRules

        let htmlRules = buildRules(for: "html")
        map["html"] = htmlRules
        map["htm"] = htmlRules
        map["xhtml"] = htmlRules

        let cssRules = buildRules(for: "css")
        map["css"] = cssRules

        let scssRules = buildRules(for: "scss")
        map["scss"] = scssRules
        map["sass"] = scssRules
        map["less"] = scssRules

        let sqlRules = buildRules(for: "sql")
        map["sql"] = sqlRules

        let mdRules = buildRules(for: "markdown")
        map["md"] = mdRules
        map["markdown"] = mdRules
        map["mdx"] = mdRules

        return map
    }()
}
