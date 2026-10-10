import SwiftTUIViews

/// Composes a parsed Markdown document from native terminal views.
/// Place this content in a native `ScrollView` when it exceeds the available height.
@MainActor
public struct MarkdownView {
    @Environment(\.chioTheme) private var theme
    private let document: MarkdownDocument
    private let links: MarkdownLinks
    private let highlighting: CodeHighlighting

    public enum CodeHighlighting {
        /// Highlights supported Swift fences; other code retains plain text.
        case automatic
        /// Displays code without token colors, preserving its native scroll view.
        case plain
    }

    /// Displays readable destinations without creating interactive links.
    public init(_ document: MarkdownDocument) {
        self.document = document
        links = .passive
        highlighting = .automatic
    }

    /// Enables native inline links with an explicit application-owned opening action.
    /// The action receives the authored destination, including relative paths and fragments.
    public init(_ document: MarkdownDocument, openLink: OpenLinkAction) {
        self.document = document
        links = .interactive(openLink)
        highlighting = .automatic
    }

    private init(document: MarkdownDocument, links: MarkdownLinks, highlighting: CodeHighlighting) {
        self.document = document
        self.links = links
        self.highlighting = highlighting
    }

    /// Returns a presentation choice without reparsing the retained document.
    public func codeHighlighting(_ highlighting: CodeHighlighting) -> Self {
        MarkdownView(document: document, links: links, highlighting: highlighting)
    }
}

extension MarkdownView.CodeHighlighting: Hashable {}
extension MarkdownView.CodeHighlighting: Codable {}
extension MarkdownView.CodeHighlighting: Sendable {}

extension MarkdownView: View {
    public var body: some View {
        MarkdownBlocks(blocks: document.blocks, theme: theme, links: links, highlighting: highlighting)
            .openLinkAction(links.action)
            .foregroundStyle(theme.colors.foreground)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum MarkdownLinks {
    case passive
    case interactive(OpenLinkAction)

    var isInteractive: Bool {
        switch self {
        case .interactive: true
        case .passive: false
        }
    }

    @MainActor
    var action: OpenLinkAction {
        switch self {
        case .passive: OpenLinkAction { _ in false }
        case let .interactive(action): action
        }
    }
}

@MainActor
private struct MarkdownBlocks {
    let blocks: [MarkdownDocument.Block]
    let theme: ChioTheme
    let links: MarkdownLinks
    let highlighting: MarkdownView.CodeHighlighting
}

extension MarkdownBlocks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            ForEach(blocks.indices, id: \.self) { index in
                MarkdownBlock(block: blocks[index], theme: theme, links: links, highlighting: highlighting)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
private struct MarkdownBlock {
    let block: MarkdownDocument.Block
    let theme: ChioTheme
    let links: MarkdownLinks
    let highlighting: MarkdownView.CodeHighlighting

    private func codeText(_ code: MarkdownCode) -> Text {
        var interpolation = Text.StringInterpolation(literalCapacity: 0, interpolationCount: code.highlights.count * 2 + 1)
        var cursor = code.text.startIndex
        switch highlighting {
        case .automatic:
            for highlight in code.highlights {
                interpolation.appendInterpolation(Text(verbatim: String(code.text[cursor..<highlight.range.lowerBound])))
                let color: Color
                switch highlight.kind {
                case .keyword: color = theme.syntax.keyword
                case .type: color = theme.syntax.type
                case .string: color = theme.syntax.string
                case .number: color = theme.syntax.number
                case .comment: color = theme.syntax.comment
                }
                interpolation.appendInterpolation(Text(verbatim: String(code.text[highlight.range])).foregroundStyle(color))
                cursor = highlight.range.upperBound
            }
        case .plain:
            break
        }
        interpolation.appendInterpolation(Text(verbatim: String(code.text[cursor...])))
        return Text(Text.RichContent(stringInterpolation: interpolation))
    }

    private func text(_ spans: [MarkdownDocument.Span], isInLink: Bool = false) -> Text {
        var interpolation = Text.StringInterpolation(
            literalCapacity: 0,
            interpolationCount: spans.count
        )
        for span in spans {
            switch span {
            case let .text(value, attributes):
                var fragment = Text(verbatim: value)
                if attributes.contains(.strong) { fragment = fragment.bold() }
                if attributes.contains(.emphasis) { fragment = fragment.italic() }
                // An active link's style owns its paint, including focus feedback.
                if attributes.contains(.code) && !isInLink {
                    fragment = fragment.foregroundStyle(theme.colors.accent)
                        .cellBackground(theme.colors.selectedSurface)
                }
                interpolation.appendInterpolation(fragment)
            case let .link(label, destination, _):
                if links.isInteractive {
                    interpolation.appendInterpolation(Link(text(label, isInLink: true), destination: destination))
                } else {
                    interpolation.appendInterpolation(text(span.passiveSpans))
                }
            }
        }
        return Text(Text.RichContent(stringInterpolation: interpolation))
    }

    private func columns(_ table: MarkdownDocument.Table) -> [TableColumn] {
        table.headers.enumerated().map { index, spans in
            // Native headers accept labels; body cells retain their rich Text runs.
            TableColumn(spans.map(\.plainText).joined(), alignment: table.alignments[index])
        }
    }
}

extension MarkdownBlock: View {
    // Type erasure confines the recursive block structure to a finite native view type.
    var body: AnyView {
        switch block {
        case let .heading(level, spans):
            return AnyView(text(spans).bold()
                .underline(level <= 2)
                .foregroundStyle(theme.colors.heading))
        case let .paragraph(spans):
            return AnyView(text(spans).paragraph())
        case let .list(items):
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 1) {
                        Text(verbatim: items[index].marker)
                            .foregroundStyle(theme.colors.accent)
                            .fixedSize()
                        MarkdownBlocks(blocks: items[index].blocks, theme: theme, links: links, highlighting: highlighting)
                    }
                }
            })
        case let .quote(blocks):
            return AnyView(HStack(alignment: .top, spacing: 1) {
                // A native leading-edge border vanishes on a one-row quote.
                // A text marker keeps the quote visible at every block height.
                Text("│").foregroundStyle(theme.colors.border).fixedSize()
                MarkdownBlocks(blocks: blocks, theme: theme, links: links, highlighting: highlighting)
                    .foregroundStyle(theme.colors.secondaryText)
            })
        case let .code(code):
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                if !code.language.isEmpty {
                    Text(verbatim: code.language).foregroundStyle(theme.colors.mutedText)
                }
                ScrollView(.horizontal) {
                    codeText(code).fixedSize()
                }
                .scrollIndicators(.hidden, axes: .horizontal)
                .frame(height: max(1, code.text.split(separator: "\n", omittingEmptySubsequences: false).count))
            }
            .padding(.horizontal, theme.spacing.horizontalInset)
            .background(theme.colors.selectedSurface))
        case let .table(table):
            return AnyView(ScrollView(.horizontal) {
                Table(columns: columns(table)) {
                    ForEach(table.rows.indices, id: \.self) { row in
                        TableRow {
                            ForEach(table.rows[row].indices, id: \.self) { column in
                                text(table.rows[row][column])
                            }
                        }
                        .listRowBackground(theme.colors.surface)
                    }
                }
                .tableStyle(ChioTableStyle(theme: theme))
                .fixedSize()
            }
            .scrollIndicators(.hidden, axes: .horizontal)
            .fixedSize(horizontal: false, vertical: true))
        case .rule:
            return AnyView(GeometryReader { geometry in
                Text(String(repeating: "─", count: max(0, geometry.size.width)))
                    .foregroundStyle(theme.colors.border)
            }.frame(height: 1))
        case let .fallback(value):
            return AnyView(Text(verbatim: value))
        }
    }
}
