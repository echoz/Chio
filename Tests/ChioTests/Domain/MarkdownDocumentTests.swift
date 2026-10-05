@testable import Chio
import Testing

struct MarkdownDocumentTests {
    @Test("All six heading levels retain their content", arguments: 1...6)
    func heading(level: Int) {
        let document = MarkdownDocument(String(repeating: "#", count: level) + " Title")
        #expect(document.blocks == [.heading(level: level, spans: [
            .text("Title", []),
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
        #expect(spans.map(\.plainText).joined() == "both and strong and emphasis and code")
        #expect(spans.contains(.text("both", [.strong, .emphasis])))
        #expect(spans.contains(.text("strong", [.strong])))
        #expect(spans.contains(.text("emphasis", [.emphasis])))
        #expect(spans.contains(.text("code", [.code])))
    }

    @Test("Soft breaks join prose and authored hard breaks retain a newline")
    func lineBreaks() {
        #expect(paragraphSpans("first\nsecond  \nthird").map(\.plainText).joined() == "first second\nthird")
    }

    @Test("Technical punctuation remains literal")
    func punctuation() {
        let source = "\"straight\" 'quotes' -- flags --- dashes"
        #expect(paragraphSpans(source).map(\.plainText).joined() == source)
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
            .paragraph([.text("seven", [])]),
            .list([.init(marker: "•", blocks: [
                .paragraph([.text("nested", [])]),
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
            .paragraph([.text("first", [])]),
            .paragraph([.text("second", [])]),
        ])
    }

    @Test("Quotes preserve their nested block structure")
    func quote() {
        let document = MarkdownDocument("> **quoted**\n>\n> > inner")
        #expect(document.blocks == [.quote([
            .paragraph([.text("quoted", [.strong])]),
            .quote([.paragraph([.text("inner", [])])]),
        ])])
    }

    @Test("Fenced code preserves indentation, blank lines, and literal punctuation")
    func fencedCode() {
        let document = MarkdownDocument("```swift\n  let x = \"--\"\n\n    print(x)\n```\n")
        #expect(document.blocks == [.code(
            language: "swift", text: "  let x = \"--\"\n\n    print(x)\n"
        )])
    }

    @Test("Unlabeled fences and indented code share parsed semantics and literal whitespace")
    func unlabeledCode() {
        let fenced = MarkdownDocument("```\nlet x = 1\n\n  end\n```\n")
        let indented = MarkdownDocument("    let x = 1\n\n      end\n")
        #expect(fenced.blocks == [.code(language: "", text: "let x = 1\n\n  end\n")])
        #expect(indented == fenced)
        #expect(Set([fenced, indented]).count == 1)
    }

    @Test("Empty link and image destinations retain labels without empty suffixes")
    func emptyDestinations() {
        #expect(paragraphSpans("[Docs]()") == [.text("Docs", [])])
        #expect(paragraphSpans("![Chart]()") == [.text("Chart", [])])
        #expect(paragraphSpans("![]()") == [.text("Image", [])])
        #expect(MarkdownDocument("[Docs](<>)") == MarkdownDocument("[Docs]()"))
        #expect(MarkdownDocument("![Chart](<>)") == MarkdownDocument("![Chart]()"))
    }

    @Test("Unsupported inline features keep labels, destinations, and literal HTML")
    func inlineFallback() {
        let spans = paragraphSpans("[Docs](https://example.com) ![Chart](plot.png) ~~old~~ <b>raw</b>")
        #expect(spans.map(\.plainText).joined()
            == "Docs (https://example.com) Chart (plot.png) old <b>raw</b>")
        #expect(paragraphSpans("<https://example.com>").map(\.plainText).joined() == "https://example.com")
    }

    @Test("HTML blocks stay literal")
    func blockFallback() {
        let html = MarkdownDocument("<div>raw</div>\n")
        #expect(html.blocks == [.fallback("<div>raw</div>\n")])
    }

    @Test("Each authored link keeps one complete styled label and its original destination")
    func links() {
        let spans = paragraphSpans("[**bold** *soft* `code`](../guide.md#intro)[again](../guide.md#intro)")
        #expect(spans == [
            .link(label: [.text("bold", [.strong]), .text(" ", []), .text("soft", [.emphasis]),
                          .text(" ", []), .text("code", [.code])],
                  destination: "../guide.md#intro", attributes: []),
            .link(label: [.text("again", [])], destination: "../guide.md#intro", attributes: []),
        ])
        #expect(paragraphSpans("[](chio:detail%20one)") == [
            .link(label: [.text("chio:detail%20one", [])], destination: "chio:detail%20one", attributes: []),
        ])
        #expect(paragraphSpans("**[jump](#details)**") == [
            .link(label: [.text("jump", [.strong])], destination: "#details", attributes: [.strong]),
        ])
        #expect(MarkdownDocument("[Docs](guide.md)") != MarkdownDocument("Docs (guide.md)"))
    }

    @Test("Tables retain headers, rich cells, empty cells, and column alignments")
    func table() throws {
        let document = MarkdownDocument("""
        | **Name** | State | Time | Note |
        | :--- | :---: | ---: | --- |
        | `swift test` | **Passed** | 3.2 s | |
        | café | Ready | 0.4 s |
        """)
        guard case let .table(table) = try #require(document.blocks.first) else {
            Issue.record("Expected a table")
            return
        }
        #expect(table.headers.map { $0.map(\.plainText).joined() } == ["Name", "State", "Time", "Note"])
        #expect(table.alignments == [.leading, .center, .trailing, .leading])
        #expect(table.rows.count == 2)
        #expect(table.rows.allSatisfy { $0.count == 4 })
        #expect(table.headers[0] == [.text("Name", [.strong])])
        #expect(table.rows[0][0] == [.text("swift test", [.code])])
        #expect(table.rows[0][1] == [.text("Passed", [.strong])])
        #expect(table.rows[0][3].isEmpty)
        #expect(table.rows[1][3].isEmpty)
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
