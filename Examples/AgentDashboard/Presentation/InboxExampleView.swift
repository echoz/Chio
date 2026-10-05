import Chio
import SwiftTUI

/// Application-owned queue policy composed from existing Chio and native views.
@MainActor
struct InboxExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var isLight: Bool
    @State private var queue = Queue.review
    @State private var order = ReviewItem.Order.recent
    @State private var query = ""
    @State private var selection: Selection?
    @State private var readerPresentation = ReaderPresentation.closed
    @State private var showsPreview = true
    @State private var isSearching = false

    init(light: Bool = false) {
        _isLight = State(wrappedValue: light)
        _selection = State(wrappedValue: ReviewItem.examples.first.map(Selection.init))
    }

    fileprivate enum Queue: String {
        case review = "Review", drafts = "Drafts", all = "All"

        var next: Self {
            switch self {
            case .review: .drafts
            case .drafts: .all
            case .all: .review
            }
        }

        func contains(_ item: ReviewItem) -> Bool {
            switch self {
            case .review: item.status != .draft
            case .drafts: item.status == .draft
            case .all: true
            }
        }
    }

    // The selection retains the parsed document across unrelated view updates.
    // This is a presentation snapshot, not another persisted review model.
    fileprivate struct Selection {
        let item: ReviewItem
        let document: MarkdownDocument

        init(item: ReviewItem) {
            self.item = item
            document = MarkdownDocument("""
            # \(item.title)

            **\(item.repository)** · #\(item.id) · @\(item.author)

            **\(item.status.title)**

            \(item.summary)

            ## Changed files

            \(item.files.map { "- `\($0)`" }.joined(separator: "\n"))

            *End of local review.*
            """)
        }
    }

    fileprivate enum ReaderPresentation {
        case closed
        case requested(Selection)
        case presented(Selection)

        var isActive: Bool {
            if case .closed = self { return false }
            return true
        }
    }

    private var presentedReader: Binding<Selection?> {
        Binding(get: {
            if case .presented(let selection) = readerPresentation { return selection }
            return nil
        }, set: { readerPresentation = $0.map(ReaderPresentation.presented) ?? .closed })
    }

    private var theme: ChioTheme {
        let base: ChioTheme = isLight ? .light : .default
        return base.replacing(spacing: base.spacing.replacing(sectionGap: 0))
    }
    private var compact: Bool { terminalSize.height < 26 || terminalSize.width < 88 }
    private var inlinePreview: Bool { !compact && showsPreview }
    private var queueWidth: Int? {
        // Two outer insets and the two-cell pane gap leave the usable width.
        inlinePreview ? max(40, (terminalSize.width - 4) * 2 / 5) : nil
    }
    private var items: [ReviewItem] {
        ReviewItem.ordered(ReviewItem.examples.filter(queue.contains), by: order)
    }

    private func select(_ id: ReviewItem.ID?) {
        guard selection?.id != id else { return }
        selection = items.first { $0.id == id }.map(Selection.init)
    }

    private var selectedID: Binding<ReviewItem.ID?> {
        Binding(get: { selection?.id }, set: select)
    }

    private var queueBinding: Binding<Queue> {
        Binding(get: { queue }, set: { value in
            queue = value
            // Clear hidden selection immediately. SearchableList chooses the
            // first matching result when it receives the new collection.
            if let selection, !value.contains(selection.item) { self.selection = nil }
        })
    }

    private func open(_ item: ReviewItem) {
        // A queue change and Return can share a read before the list updates.
        guard queue.contains(item) else { return }
        let snapshot = selection.flatMap { $0.id == item.id ? $0 : nil } ?? Selection(item: item)
        readerPresentation = .requested(snapshot)
    }

    private func handleKey(_ press: KeyPress) -> KeyPressResult {
        // Cover presentation follows a frame; consume input during that handoff.
        if readerPresentation.isActive {
            if press.key == .escape { readerPresentation = .closed }
            if press == KeyPress(.character("t"), modifiers: .ctrl) { isLight.toggle() }
            return .handled
        }
        guard press.modifiers == .ctrl else { return .ignored }
        switch press.key {
        case .character("g"): queueBinding.wrappedValue = queue.next
        case .character("s"): order = order.next
        case .character("p"): showsPreview.toggle()
        case .character("t"): isLight.toggle()
        case .character("q"): _ = requestTermination()
        default: return .ignored
        }
        return .handled
    }

    private func row(_ item: ReviewItem) -> some View {
        let symbol: String
        let color: Color
        switch item.status {
        case .review: symbol = "●"; color = theme.colors.accent
        case .draft: symbol = "○"; color = theme.colors.mutedText
        case .changesRequested: symbol = "!"; color = theme.colors.warning
        }
        var text = Text.StringInterpolation(literalCapacity: 0, interpolationCount: 3)
        text.appendInterpolation(Text("#\(item.id) ").foregroundStyle(theme.colors.mutedText))
        text.appendInterpolation(Text("\(symbol) ").foregroundStyle(color))
        text.appendInterpolation(Text(verbatim: item.title))
        return Text(Text.RichContent(stringInterpolation: text))
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel("#\(item.id) \(item.title), \(item.repository), \(item.status.title)")
    }

    private var hints: some View {
        KeyHints {
            KeyHint(isSearching ? "↵" : "↑↓", isSearching ? "results" : "select")
            KeyHint("↵", "read")
            KeyHint("/", "filter")
            KeyHint("^G", "queue")
            KeyHint("^S", "sort")
            if !compact { KeyHint("^P", "preview") }
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }

    @MainActor
    fileprivate struct Reader {
        let selection: Selection
        @Binding var isLight: Bool
        let close: @MainActor @Sendable () -> Void
        @FocusState private var reading: Bool
    }
}

extension InboxExampleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ review inbox").foregroundStyle(theme.colors.secondaryText)
                Spacer(minLength: 1)
                Text("local").foregroundStyle(theme.colors.mutedText)
            }
            if !compact {
                Text("A quiet place to review. Fixed fixtures; no GitHub connection.")
                    .foregroundStyle(theme.colors.mutedText)
                Spacer().frame(height: 1)
            }
            HStack(spacing: 1) {
                Picker("Queue", selection: queueBinding) {
                    ForEach([Queue.review, .drafts, .all], id: \.self) { queue in
                        Text("\(queue.rawValue) (\(ReviewItem.examples.filter(queue.contains).count))").tag(queue)
                    }
                }
                .frame(width: 20)
                Picker("Sort order", selection: $order) {
                    Text(ReviewItem.Order.recent.title).tag(ReviewItem.Order.recent)
                    Text(ReviewItem.Order.repository.title).tag(ReviewItem.Order.repository)
                }
            }
            .pickerStyle(ChioPickerStyle(theme: theme, showsLabel: false))

            // The list stays at this structural position when the preview vanishes.
            HStack(alignment: .top, spacing: 2) {
                GroupBox("Queue") {
                    SearchableList(items, selection: selectedID, query: $query,
                                   prompt: "Filter reviews…", searchText: \.searchText, rowContent: row)
                        .filtering(.substring)
                        .onActivate(open)
                        .onSearchFocusChange { isSearching = $0 }
                        .onResultKeyPress(perform: handleKey)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(width: queueWidth)
                if inlinePreview {
                    GroupBox("Preview") {
                        ScrollView {
                            if let selection {
                                MarkdownView(selection.document)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("No review selected.").foregroundStyle(theme.colors.mutedText)
                            }
                        }
                        .disabled(true)
                        .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .groupBoxStyle(ChioGroupBoxStyle(theme: theme, titlePlacement: .border))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text(selection.map { "#\($0.id) · \($0.item.repository) · @\($0.item.author) · \($0.item.status.title)" }
                ?? "No review selected.")
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
            if compact { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, compact ? 0 : 1)
        .padding(.vertical, compact ? 0 : 1)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .topLeading)
        .chioTheme(theme)
        .onKeyPress(perform: handleKey)
        .onChange(of: readerPresentation) { _, _ in
            // A committed background frame lets native results focus settle
            // before the cover captures it for restoration. Read live state so
            // Escape during the handoff cannot be undone by this callback.
            if case .requested(let selection) = readerPresentation {
                readerPresentation = .presented(selection)
            }
        }
        .fullScreenCover(item: presentedReader) { selection in
            Reader(selection: selection, isLight: $isLight, close: { readerPresentation = .closed })
        }
    }
}

extension InboxExampleView.Queue: Hashable {}
extension InboxExampleView.Queue: Codable {}
extension InboxExampleView.Queue: Sendable {}

extension InboxExampleView.Selection: Identifiable {
    var id: ReviewItem.ID { item.id }
}
extension InboxExampleView.Selection: Hashable {}
extension InboxExampleView.Selection: Sendable {}

extension InboxExampleView.ReaderPresentation: Hashable {}
extension InboxExampleView.ReaderPresentation: Sendable {}

extension InboxExampleView.Reader: View {
    var body: some View {
        let theme: ChioTheme = isLight ? .light : .default
        VStack(alignment: .leading, spacing: 1) {
            Text("chio / review #\(selection.id)").bold().foregroundStyle(theme.colors.accent)
            ScrollView {
                MarkdownView(selection.document)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($reading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            StatusBar {
                KeyHints {
                    KeyHint("↑↓", "scroll")
                    KeyHint("home/end", "jump")
                    KeyHint("esc", "back")
                    KeyHint("^T", "theme")
                }
            }
        }
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chioTheme(theme)
        .onAppear { reading = true }
        .onKeyPress { press in
            if press.key == .escape { close(); return .handled }
            if press == KeyPress(.character("t"), modifiers: .ctrl) {
                isLight.toggle()
                return .handled
            }
            return .ignored
        }
    }
}
