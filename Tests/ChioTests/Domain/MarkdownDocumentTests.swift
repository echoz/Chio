@testable import Chio
import Testing

struct MarkdownDocumentTests {
    @Test("All six heading levels retain their content", arguments: 1...6)
    func heading(level: Int) {
        let document = MarkdownDocument(String(repeating: "#", count: level) + " Title")
        #expect(document.blocks == [.heading(level: level, spans: [
            .init(text: "Title", attributes: []),
        ])])
    }

    @Test("Empty input has no document blocks")
    func empty() {
        #expect(MarkdownDocument("").blocks.isEmpty)
        #expect(MarkdownDocument("\n \n").blocks.isEmpty)
    }

    @Test("Nested inline emphasis accumulates without changing readable content")
    func inlineAttributes() {
        let spans = paragraphSpans("***both*** and **strong** and *emphasis* and `code`")
        #expect(spans.map(\.text).joined() == "both and strong and emphasis and code")
        #expect(spans.first { $0.text == "both" }?.attributes == [.strong, .emphasis])
        #expect(spans.first { $0.text == "strong" }?.attributes == [.strong])
        #expect(spans.first { $0.text == "emphasis" }?.attributes == [.emphasis])
        #expect(spans.first { $0.text == "code" }?.attributes == [.code])
    }

    @Test("Soft breaks join prose and authored hard breaks retain a newline")
    func lineBreaks() {
        #expect(paragraphSpans("first\nsecond  \nthird").map(\.text).joined() == "first second\nthird")
    }

    @Test("Technical punctuation remains literal")
    func punctuation() {
        let source = "\"straight\" 'quotes' -- flags --- dashes"
        #expect(paragraphSpans(source).map(\.text).joined() == source)
    }

    @Test("Ordered starts, nested lists, and task markers remain distinct")
    func lists() throws {
        let document = MarkdownDocument("""
        7. seven
           - nested
        8. eight

        - [x] done
        - [ ] pending
        """)
        #expect(document.blocks.count == 2)
        guard case let .list(items) = try #require(document.blocks.first) else {
            Issue.record("Expected the ordered list")
            return
        }
        #expect(items.map(\.marker) == ["7.", "8."])
        #expect(items[0].blocks == [
            .paragraph([.init(text: "seven", attributes: [])]),
            .list([.init(marker: "•", blocks: [
                .paragraph([.init(text: "nested", attributes: [])]),
            ])]),
        ])
        guard case let .list(tasks) = try #require(document.blocks.last) else {
            Issue.record("Expected the task list")
            return
        }
        #expect(tasks.map(\.marker) == ["• [x]", "• [ ]"])
    }

    @Test("List items preserve separate paragraphs")
    func listParagraphs() throws {
        let document = MarkdownDocument("- first\n\n  second\n")
        guard case let .list(items) = try #require(document.blocks.first) else {
            Issue.record("Expected a list")
            return
        }
        #expect(items[0].blocks == [
            .paragraph([.init(text: "first", attributes: [])]),
            .paragraph([.init(text: "second", attributes: [])]),
        ])
    }

    @Test("Quotes preserve their nested block structure")
    func quote() {
        let document = MarkdownDocument("> **quoted**\n>\n> > inner")
        #expect(document.blocks == [.quote([
            .paragraph([.init(text: "quoted", attributes: [.strong])]),
            .quote([.paragraph([.init(text: "inner", attributes: [])])]),
        ])])
    }

    @Test("Fenced code preserves indentation, blank lines, and literal punctuation")
    func fencedCode() {
        let document = MarkdownDocument("```swift\n  let x = \"--\"\n\n    print(x)\n```\n")
        #expect(document.blocks == [.code(
            language: "swift", text: "  let x = \"--\"\n\n    print(x)\n"
        )])
    }

    @Test("Unsupported inline features keep labels, destinations, and literal HTML")
    func inlineFallback() {
        let spans = paragraphSpans("[Docs](https://example.com) ![Chart](plot.png) ~~old~~ <b>raw</b>")
        #expect(spans.map(\.text).joined()
            == "Docs (https://example.com) Chart (plot.png) old <b>raw</b>")
        #expect(paragraphSpans("<https://example.com>").map(\.text).joined() == "https://example.com")
    }

    @Test("Table fallback preserves rows and cell boundaries; HTML stays literal")
    func blockFallback() {
        let table = MarkdownDocument("| Name | State |\n| --- | --- |\n| A | done |\n")
        #expect(table.blocks == [.fallback("Name | State\nA | done")])
        let html = MarkdownDocument("<div>raw</div>\n")
        #expect(html.blocks == [.fallback("<div>raw</div>\n")])
    }

    @Test("Document equality compares parsed semantics")
    func equality() {
        #expect(MarkdownDocument("**same**") == MarkdownDocument("__same__"))
        #expect(MarkdownDocument("same") != MarkdownDocument("**same**"))
        #expect(MarkdownDocument("# Title") != MarkdownDocument("## Title"))
    }

    private func paragraphSpans(_ source: String) -> [MarkdownDocument.Span] {
        guard let first = MarkdownDocument(source).blocks.first,
              case let .paragraph(spans) = first else {
            Issue.record("Expected a paragraph")
            return []
        }
        return spans
    }
}
