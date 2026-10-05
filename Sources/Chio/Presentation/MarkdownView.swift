import SwiftTUIViews

/// Composes a parsed Markdown document from native terminal views.
/// Place this content in a native `ScrollView` when it exceeds the available height.
@MainActor
public struct MarkdownView {
    @Environment(\.chioTheme) private var theme
    private let document: MarkdownDocument

    public init(_ document: MarkdownDocument) {
        self.document = document
    }
}

extension MarkdownView: View {
    public var body: some View {
        MarkdownBlocks(blocks: document.blocks, theme: theme)
            .foregroundStyle(theme.colors.foreground)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
private struct MarkdownBlocks {
    let blocks: [MarkdownDocument.Block]
    let theme: ChioTheme
}

extension MarkdownBlocks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            ForEach(blocks.indices, id: \.self) { index in
                MarkdownBlock(block: blocks[index], theme: theme)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
private struct MarkdownBlock {
    let block: MarkdownDocument.Block
    let theme: ChioTheme

    private func text(_ spans: [MarkdownDocument.Span]) -> Text {
        var interpolation = Text.StringInterpolation(
            literalCapacity: 0,
            interpolationCount: spans.count
        )
        for span in spans {
            var fragment = Text(verbatim: span.text)
            if span.attributes.contains(.strong) { fragment = fragment.bold() }
            if span.attributes.contains(.emphasis) { fragment = fragment.italic() }
            if span.attributes.contains(.code) {
                fragment = fragment.foregroundStyle(theme.colors.accent)
                    .cellBackground(theme.colors.selectedSurface)
            }
            interpolation.appendInterpolation(fragment)
        }
        return Text(Text.RichContent(stringInterpolation: interpolation))
    }

    private func columns(_ table: MarkdownDocument.Table) -> [TableColumn] {
        table.headers.enumerated().map { index, spans in
            // Native headers accept labels; body cells retain their rich Text runs.
            TableColumn(spans.map(\.text).joined(), alignment: table.alignments[index])
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
                        MarkdownBlocks(blocks: items[index].blocks, theme: theme)
                    }
                }
            })
        case let .quote(blocks):
            return AnyView(HStack(alignment: .top, spacing: 1) {
                // A native leading-edge border vanishes on a one-row quote.
                // A text marker keeps the quote visible at every block height.
                Text("│").foregroundStyle(theme.colors.border).fixedSize()
                MarkdownBlocks(blocks: blocks, theme: theme)
                    .foregroundStyle(theme.colors.secondaryText)
            })
        case let .code(language, code):
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                if !language.isEmpty {
                    Text(verbatim: language).foregroundStyle(theme.colors.mutedText)
                }
                ScrollView(.horizontal) {
                    Text(verbatim: code).fixedSize()
                }
                .scrollIndicators(.hidden, axes: .horizontal)
                .frame(height: max(1, code.split(separator: "\n", omittingEmptySubsequences: false).count))
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
