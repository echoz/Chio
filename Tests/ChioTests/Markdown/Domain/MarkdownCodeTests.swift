@testable import Chio
import Testing

struct MarkdownCodeTests {
    @Test("Swift classifications color five semantic roles and leave identifiers intact")
    func roles() {
        let code = MarkdownCode(language: "Swift title=demo", text: "let name: String = \"Chio\" // hello\nlet count = 42\n")
        let tokens = code.highlights.map { (String(code.text[$0.range]), $0.kind) }
        #expect(tokens.contains { $0 == ("let", .keyword) })
        #expect(tokens.contains { $0 == ("String", .type) })
        #expect(tokens.contains { $0.0.contains("Chio") && $0.1 == .string })
        #expect(tokens.contains { $0 == ("42", .number) })
        #expect(tokens.contains { $0.0.contains("// hello") && $0.1 == .comment })
        #expect(!tokens.contains { $0.0.contains("name") || $0.0.contains("count") })
    }

    @Test("Unrecognized and absent language hints retain plain source", arguments: ["", "sh", "rust", "swiftish"])
    func unsupported(language: String) {
        let text = "\tlet name = \"Chio\"\n\n"
        let code = MarkdownCode(language: language, text: text)
        #expect(code.text.utf8.elementsEqual(text.utf8))
        #expect(code.highlights.isEmpty)
    }

    @Test("Modern, incomplete and Unicode Swift retain every source byte", arguments: [
        "actor Worker { func run() async throws { await task() } }\n",
        "let unfinished: String = \"hello\nfunc work( {\n",
        "/* outer /* inner */ end */\nlet raw = #\"\\n\"#\n",
        "\tlet cafe\u{301} = \"界 👩‍💻\"\n\n// cafe\u{301}\n",
        "let value = 1\r\n\r\n",
        "let value = " + String(repeating: "[", count: 128) + "1" + String(repeating: "]", count: 128),
        "", "\n\t  \n",
    ])
    func sourceIntegrity(text: String) {
        let code = MarkdownCode(language: "swift", text: text)
        let boundaries = Set(text.indices).union([text.endIndex])
        var reconstructed = ""
        var cursor = text.startIndex
        for highlight in code.highlights {
            #expect(boundaries.contains(highlight.range.lowerBound))
            #expect(boundaries.contains(highlight.range.upperBound))
            #expect(highlight.range.lowerBound >= cursor)
            reconstructed += text[cursor..<highlight.range.lowerBound]
            reconstructed += text[highlight.range]
            cursor = highlight.range.upperBound
        }
        reconstructed += text[cursor...]
        #expect(code.text.utf8.elementsEqual(text.utf8))
        #expect(reconstructed.utf8.elementsEqual(text.utf8))
    }

    @Test("The code-byte bound preserves large blocks as plain text")
    func sizeBound() {
        let prefix = "let name = 1\n// "
        let limit = prefix + String(repeating: "x", count: 65_536 - prefix.utf8.count)
        #expect(!MarkdownCode(language: "swift", text: limit).highlights.isEmpty)
        let over = limit + "x"
        let code = MarkdownCode(language: "swift", text: over)
        #expect(code.text == over)
        #expect(code.highlights.isEmpty)
        let unicode = "// " + String(repeating: "界", count: 22_000)
        #expect(MarkdownCode(language: "swift", text: unicode).highlights.isEmpty)
    }

    @Test("Deeply nested code preserves the entire original source")
    func nestingBound() {
        let text = "let value = " + String(repeating: "[", count: 128)
            + "1" + String(repeating: "]", count: 128)
        let code = MarkdownCode(language: "swift", text: text)
        #expect(code.text.utf8.elementsEqual(text.utf8))
        #expect(code.highlights.contains { $0.kind == .keyword })
    }

    @Test("Parser work cancellation returns plain annotations without changing source")
    func workBound() {
        let text = "let value = " + String(repeating: "[", count: 32_000)
            + "1" + String(repeating: "]", count: 32_000)
        #expect(text.utf8.count < 65_536)
        let code = MarkdownCode(language: "swift", text: text)
        #expect(code.text.utf8.elementsEqual(text.utf8))
        #expect(MarkdownCode.classify(text, language: "swift", checkpointLimit: 1).isEmpty)
        #expect(MarkdownCode(language: "swift", text: "let value = 1").highlights.contains { $0.kind == .keyword })
    }

    @Test("Markdown normalizes CRLF before source-accurate classification")
    func lineEndings() throws {
        let document = MarkdownDocument("```swift\r\nlet value = 1\r\n\r\n```\r\n")
        guard case let .code(code) = try #require(document.blocks.first) else {
            Issue.record("Expected a fenced code block")
            return
        }
        #expect(code.text == "let value = 1\n\n")
        #expect(!code.highlights.isEmpty)
    }
}
