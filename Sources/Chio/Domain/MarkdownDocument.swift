import Markdown
import SwiftTUIViews

/// An immutable, parsed Markdown document, independent of terminal presentation.
/// Create this value when the source changes and reuse it across view updates.
public struct MarkdownDocument {
    let blocks: [Block]

    public init(_ source: String) {
        let document = Markdown.Document(parsing: source, options: [.disableSmartOpts])
        blocks = Self.blockChildren(of: document)
    }

    indirect enum Block {
        case heading(level: Int, spans: [Span])
        case paragraph([Span])
        case list([Item])
        case quote([Block])
        case code(language: String, text: String)
        case table(Table)
        case rule
        case fallback(String)
    }

    struct Item {
        let marker: String
        let blocks: [Block]
    }

    indirect enum Span {
        case text(String, Attributes)
        case link(label: [Span], destination: LinkDestination, attributes: Attributes)

        /// Readable fallback for passive documents and native plain-text headers.
        var plainText: String {
            switch self {
            case let .text(value, _): return value
            case let .link(label, destination, _):
                let text = label.map(\.plainText).joined()
                return text == destination.rawValue ? text : "\(text) (\(destination.rawValue))"
            }
        }

        /// Removes activation while preserving readable text and inline styles.
        var passiveSpans: [Span] {
            switch self {
            case .text: return [self]
            case let .link(label, destination, attributes):
                let suffix: [Span] = label.map(\.plainText).joined() == destination.rawValue
                    ? [] : [.text(" (\(destination.rawValue))", attributes)]
                return label.flatMap(\.passiveSpans) + suffix
            }
        }
    }

    struct Table {
        let headers: [[Span]]
        let rows: [[[Span]]]
        let alignments: [TableColumnAlignment]
    }

    struct Attributes {
        let rawValue: UInt8
        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        static let strong = Self(rawValue: 1 << 0)
        static let emphasis = Self(rawValue: 1 << 1)
        static let code = Self(rawValue: 1 << 2)
    }
}

extension MarkdownDocument: Equatable {}
extension MarkdownDocument: Hashable {}
extension MarkdownDocument: Sendable {}
extension MarkdownDocument.Block: Equatable {}
extension MarkdownDocument.Block: Hashable {}
extension MarkdownDocument.Block: Sendable {}
extension MarkdownDocument.Item: Equatable {}
extension MarkdownDocument.Item: Hashable {}
extension MarkdownDocument.Item: Sendable {}
extension MarkdownDocument.Span: Equatable {}
extension MarkdownDocument.Span: Hashable {}
extension MarkdownDocument.Span: Sendable {}
extension MarkdownDocument.Table: Equatable {}
extension MarkdownDocument.Table: Hashable {}
extension MarkdownDocument.Table: Sendable {}
extension MarkdownDocument.Attributes: Equatable {}
extension MarkdownDocument.Attributes: Hashable {}
extension MarkdownDocument.Attributes: Sendable {}

extension MarkdownDocument.Attributes: OptionSet {}

private extension MarkdownDocument {
    static func blockChildren(of node: any Markup) -> [Block] {
        node.children.flatMap(blocks(from:))
    }

    static func blocks(from node: any Markup) -> [Block] {
        switch node {
        case let heading as Markdown.Heading:
            return [.heading(level: heading.level, spans: inlineChildren(of: heading))]
        case let paragraph as Markdown.Paragraph:
            return [.paragraph(inlineChildren(of: paragraph))]
        case let list as Markdown.OrderedList:
            let items = list.children.enumerated().compactMap { index, child -> Item? in
                guard let item = child as? Markdown.ListItem else { return nil }
                return listItem(item, marker: "\(list.startIndex + UInt(index)).")
            }
            return [.list(items)]
        case let list as Markdown.UnorderedList:
            let items = list.children.compactMap { child -> Item? in
                guard let item = child as? Markdown.ListItem else { return nil }
                return listItem(item, marker: "•")
            }
            return [.list(items)]
        case let quote as Markdown.BlockQuote:
            return [.quote(blockChildren(of: quote))]
        case let code as Markdown.CodeBlock:
            return [.code(language: code.language ?? "", text: code.code)]
        case is Markdown.ThematicBreak:
            return [.rule]
        case let html as Markdown.HTMLBlock:
            return [.fallback(html.rawHTML)]
        case let table as Markdown.Table:
            return [.table(Table(
                headers: table.head.cells.map { inlineChildren(of: $0) },
                rows: table.body.rows.map { row in row.cells.map { inlineChildren(of: $0) } },
                alignments: table.columnAlignments.map {
                    switch $0 {
                    case .center: .center
                    case .right: .trailing
                    case .left, nil: .leading
                    }
                }
            ))]
        default:
            if !node.isEmpty { return blockChildren(of: node) }
            return [.fallback(node.format())]
        }
    }

    static func listItem(_ item: Markdown.ListItem, marker: String) -> Item {
        let visibleMarker: String
        switch item.checkbox {
        case .checked: visibleMarker = "\(marker) [x]"
        case .unchecked: visibleMarker = "\(marker) [ ]"
        case nil: visibleMarker = marker
        }
        return Item(marker: visibleMarker, blocks: blockChildren(of: item))
    }

    static func inlineChildren(
        of node: any Markup,
        attributes: Attributes = []
    ) -> [Span] {
        node.children.flatMap { spans(from: $0, attributes: attributes) }
    }

    static func spans(from node: any Markup, attributes: Attributes) -> [Span] {
        switch node {
        case let text as Markdown.Text:
            return [.text(text.string, attributes)]
        case is Markdown.Strong:
            return inlineChildren(of: node, attributes: attributes.union(.strong))
        case is Markdown.Emphasis:
            return inlineChildren(of: node, attributes: attributes.union(.emphasis))
        case let code as Markdown.InlineCode:
            return [.text(code.code, attributes.union(.code))]
        case is Markdown.SoftBreak:
            return [.text(" ", attributes)]
        case is Markdown.LineBreak:
            return [.text("\n", attributes)]
        case let link as Markdown.Link:
            return referenceSpans(of: link, destination: link.destination ?? "", attributes: attributes)
        case let image as Markdown.Image:
            // Markdown permits links inside alt text; an image fallback is passive.
            let label = inlineChildren(of: image, attributes: attributes).flatMap(\.passiveSpans)
            let readableLabel = label.isEmpty ? [Span.text("Image", attributes)] : label
            return readableLabel + destinationSpan(image.source ?? "", attributes: attributes)
        case let html as Markdown.InlineHTML:
            return [.text(html.rawHTML, attributes)]
        default:
            // Strikethrough and future inline containers retain their readable descendants.
            if !node.isEmpty { return inlineChildren(of: node, attributes: attributes) }
            return [.text(node.format(), attributes)]
        }
    }

    static func referenceSpans(
        of node: any Markup,
        destination: String,
        attributes: Attributes
    ) -> [Span] {
        let label = inlineChildren(of: node, attributes: attributes)
        guard !destination.isEmpty else { return label }
        // Keep the complete label under one link, including mixed inline styles.
        // A destination-only link still needs a visible, focusable label.
        let readableLabel = label.map(\.plainText).joined().isEmpty
            ? [.text(destination, attributes)] : label
        return [.link(label: readableLabel, destination: LinkDestination(destination), attributes: attributes)]
    }

    static func destinationSpan(_ destination: String, attributes: Attributes) -> [Span] {
        guard !destination.isEmpty else { return [] }
        return [.text(" (\(destination))", attributes)]
    }

}
