import TreeSitter
import TreeSitterSwift

/// Parsed code remains authoritative; highlighting is a cached, optional annotation.
/// All ranges refer to grapheme boundaries in this value's original text.
struct MarkdownCode {
    let language: String
    let text: String
    let highlights: [Highlight]

    init(language: String, text: String) {
        self.language = language
        self.text = text
        highlights = Self.classify(text, language: language)
    }

    struct Highlight {
        let range: Range<String.Index>
        let kind: Kind
    }

    enum Kind {
        case keyword, type, string, number, comment

        init?(node: TSNode) {
            guard let name = ts_node_type(node) else { return nil }
            switch String(cString: name) {
            case "type_identifier": self = .type
            case "line_string_literal", "multi_line_string_literal", "raw_string_literal": self = .string
            case "integer_literal", "hex_literal", "oct_literal", "bin_literal", "real_literal": self = .number
            case "comment", "multiline_comment": self = .comment
            case "actor", "as", "associatedtype", "async", "await", "break", "case", "catch",
                 "class", "continue", "convenience", "default", "defer", "deinit", "do", "else",
                 "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func", "get",
                 "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is",
                 "let", "nil", "nonisolated", "open", "operator", "override", "package", "private",
                 "protocol", "public", "repeat", "required", "rethrows", "return", "self", "Self",
                 "set", "some", "any", "static", "struct", "subscript", "super", "switch", "throw",
                 "throws", "true", "try", "typealias", "unowned", "var", "weak", "where", "while",
                 "willSet", "didSet", "boolean_literal", "nil_literal", "self_expression", "super_expression",
                 "visibility_modifier", "member_modifier", "function_modifier", "property_modifier",
                 "parameter_modifier", "inheritance_modifier", "mutation_modifier", "where_keyword",
                 "getter_specifier", "setter_specifier", "modify_specifier", "as_operator", "try_operator",
                 "throw_keyword", "catch_keyword", "default_keyword": self = .keyword
            default: return nil
            }
        }
    }

    // Keep the work policy explicit so cancellation can be tested against the
    // real parser without relying on a particular grammar's complexity.
    static func classify(_ source: String, language: String, checkpointLimit: Int = 4_096) -> [Highlight] {
        guard language.split(whereSeparator: \.isWhitespace).first?.lowercased() == "swift",
              source.utf8.count <= 65_536, !source.isEmpty, checkpointLimit > 0,
              let parser = ts_parser_new() else { return [] }
        defer { ts_parser_delete(parser) }
        guard ts_parser_set_language(parser, tree_sitter_swift()) else { return [] }

        let bytes = Array(source.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            withUnsafePointer(to: buffer) { inputBuffer in
                // Mutable scratch storage belongs to this synchronous parse only.
                // A deterministic work budget avoids clock reads and background work.
                var remainingCheckpoints = checkpointLimit
                return withUnsafeMutablePointer(to: &remainingCheckpoints) { remaining in
                    let input = TSInput(
                        payload: UnsafeMutableRawPointer(mutating: inputBuffer),
                        read: { payload, offset, _, length in
                            guard let payload, let length else { return nil }
                            let buffer = payload.assumingMemoryBound(to: UnsafeBufferPointer<UInt8>.self).pointee
                            let start = Int(offset)
                            guard start < buffer.count, let base = buffer.baseAddress else {
                                length.pointee = 0
                                return nil
                            }
                            length.pointee = UInt32(buffer.count - start)
                            return UnsafeRawPointer(base.advanced(by: start)).assumingMemoryBound(to: CChar.self)
                        },
                        encoding: TSInputEncodingUTF8,
                        decode: nil
                    )
                    let options = TSParseOptions(payload: remaining, progress_callback: { state in
                        guard let payload = state?.pointee.payload else { return true }
                        let remaining = payload.assumingMemoryBound(to: Int.self)
                        remaining.pointee -= 1
                        return remaining.pointee <= 0
                    })
                    guard let tree = ts_parser_parse_with_options(parser, nil, input, options) else { return [] }
                    defer { ts_tree_delete(tree) }
                    return highlights(in: source, tree: tree)
                }
            }
        }
    }

    private static func highlights(in source: String, tree: OpaquePointer) -> [Highlight] {
        // Native rich Text clusters each styled run separately. A token boundary
        // inside a grapheme could change layout, so retain paint only when safe.
        var boundaries: [Int: String.Index] = [:]
        var offset = 0
        for index in source.indices {
            boundaries[offset] = index
            offset += source[index].utf8.count
        }
        boundaries[offset] = source.endIndex

        var cursor = ts_tree_cursor_new(ts_tree_root_node(tree))
        defer { ts_tree_cursor_delete(&cursor) }
        var previousEnd = 0
        var highlights: [Highlight] = []
        while true {
            let node = ts_tree_cursor_current_node(&cursor)
            let lower = Int(ts_node_start_byte(node))
            let upper = Int(ts_node_end_byte(node))
            if upper > lower, let kind = Kind(node: node) {
                guard lower >= previousEnd, let start = boundaries[lower], let end = boundaries[upper] else { return [] }
                highlights.append(Highlight(range: start..<end, kind: kind))
                previousEnd = upper
                // Whole strings and comments keep one role, including their children.
            } else if ts_tree_cursor_goto_first_child(&cursor) {
                continue
            }
            while !ts_tree_cursor_goto_next_sibling(&cursor) {
                guard ts_tree_cursor_goto_parent(&cursor) else { return highlights }
            }
        }
    }
}

extension MarkdownCode: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.language == rhs.language && lhs.text == rhs.text
    }
}

extension MarkdownCode: Hashable {
    func hash(into hasher: inout Hasher) {
        // Derived paint cannot change canonical Unicode document equality.
        hasher.combine(language)
        hasher.combine(text)
    }
}
extension MarkdownCode: Sendable {}
extension MarkdownCode.Highlight: Hashable {}
extension MarkdownCode.Highlight: Sendable {}
extension MarkdownCode.Kind: Hashable {}
extension MarkdownCode.Kind: Sendable {}
