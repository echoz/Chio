import Chio
import SwiftTUI

/// A small local reading prototype. Source ingestion and review actions are absent.
@MainActor
struct DiffExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var themeChoice: ExampleTheme
    @State private var fileIndex: Int
    @State private var prefersSplit: Bool
    @State private var activeHunk: Int?
    @State private var position = ScrollCellOffset.zero
    @FocusState private var isReaderFocused: Bool
    private let files = DiffFile.examples
    private let sourceWidths: [Int]

    init(theme: ExampleTheme = .default, initialFile: Int = 0, isSplit: Bool = true) {
        precondition(DiffFile.examples.indices.contains(initialFile))
        _themeChoice = State(wrappedValue: theme)
        _fileIndex = State(wrappedValue: initialFile)
        _prefersSplit = State(wrappedValue: isSplit)
        _activeHunk = State(wrappedValue: DiffFile.examples[initialFile].hunks.indices.first)
        sourceWidths = DiffFile.examples.map(Self.sourceWidth)
    }

    private var theme: ChioTheme { themeChoice.theme }
    private var file: DiffFile { files[fileIndex] }
    private var isCompact: Bool { terminalSize.height < 24 }
    private var canSplit: Bool { terminalSize.width >= 92 }
    private var isSplit: Bool { prefersSplit && canSplit }
    private var contentWidth: Int { max(1, terminalSize.width - (isCompact ? 1 : 3)) }

    private static func sourceWidth(_ file: DiffFile) -> Int {
        file.hunks.flatMap(\.blocks).reduce(0) { width, block in
            let lines: [String]
            switch block {
            case .context(let text): lines = [text]
            case .change(let removed, let added): lines = removed + added
            }
            return lines.reduce(width) { max($0, layoutText(for: $1, width: nil).size.width) }
        }
    }

    private func selectFile(_ index: Int) {
        fileIndex = index
        activeHunk = files[index].hunks.indices.first
        position = .zero
    }

    private func moveHunk(_ delta: Int) {
        guard let current = activeHunk else { return }
        activeHunk = min(max(0, current + delta), file.hunks.count - 1)
    }

    private func revealHunk(_ proxy: ScrollViewProxy) {
        guard let activeHunk else { return }
        proxy.scrollTo(DiffFileView.HunkAnchor(fileID: file.id, index: activeHunk), anchor: .topLeading)
    }

    private var hints: some View {
        KeyHints {
            KeyHint("↑↓←→", "scroll")
            KeyHint("[ ]", "hunks")
            KeyHint("^L", "view")
            KeyHint("^F", "file")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }

    private var readingStatus: String {
        let mode = isSplit ? "Split" : "Unified"
        let target = activeHunk.map { "hunk \($0 + 1)/\(file.hunks.count)" } ?? "summary"
        return "\(mode) · \(target) · +\(file.addedLineCount) −\(file.removedLineCount)"
    }

    private func handleKey(_ press: KeyPress) -> KeyPressResult {
        if press.modifiers == .ctrl {
            switch press.key {
            case .character("l") where canSplit: prefersSplit.toggle()
            case .character("f"): selectFile((fileIndex + 1) % files.count)
            case .character("t"): themeChoice = themeChoice.next
            case .character("q"): _ = requestTermination()
            default: return .ignored
            }
            return .handled
        }
        if press == KeyPress(.functionKey(6)) {
            isReaderFocused = true
            return .handled
        }
        guard isReaderFocused, press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .character("]"): moveHunk(1)
        case .character("["): moveHunk(-1)
        default: return .ignored
        }
        return .handled
    }
}

extension DiffExampleView: View {
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text("chio").bold().foregroundStyle(theme.colors.accent)
                    Text("/ changes").foregroundStyle(theme.colors.secondaryText)
                    Spacer(minLength: 0)
                    if canSplit { Text("local prototype").foregroundStyle(theme.colors.mutedText) }
                }
                if !isCompact {
                    Text("Read the change. Keep the context.").foregroundStyle(theme.colors.mutedText)
                    Spacer().frame(height: 1)
                }
                Picker("File", selection: Binding(get: { fileIndex }, set: selectFile)) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, item in
                        Text(item.path).tag(index)
                    }
                }
                .pickerStyle(ChioPickerStyle(theme: theme, showsLabel: false))
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 1) {
                    Button("‹") { moveHunk(-1) }
                        .accessibilityLabel("Previous hunk")
                        .disabled(activeHunk == nil || activeHunk == 0)
                    Button("›") { moveHunk(1) }
                        .accessibilityLabel("Next hunk")
                        .disabled(activeHunk == nil || activeHunk == file.hunks.indices.last)
                    Button(isSplit ? "Use unified" : "Use split") { prefersSplit.toggle() }
                        .disabled(!canSplit)
                }
                Text(readingStatus).foregroundStyle(theme.colors.secondaryText).lineLimit(1)
                ScrollView([.horizontal, .vertical], position: $position) {
                    DiffFileView(file: file, isSplit: isSplit, minimumWidth: contentWidth,
                                 sourceWidth: sourceWidths[fileIndex], activeHunk: activeHunk)
                }
                .focused($isReaderFocused)
                .defaultFocus($isReaderFocused, true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if !isCompact {
                    Text("Read-only fixtures · Tab controls · F6 reader · source lines scroll without wrapping")
                        .foregroundStyle(theme.colors.mutedText).lineLimit(1)
                }
                if isCompact { hints } else { StatusBar { hints } }
            }
            .padding(isCompact ? 0 : 1)
            .frame(width: terminalSize.width, height: terminalSize.height, alignment: .topLeading)
            .chioTheme(theme)
            .onKeyPress(perform: handleKey)
            // Reveal after layout commits, using the retained logical target even
            // when view/file commands arrive in the same terminal input batch.
            .onChange(of: activeHunk) { _, _ in revealHunk(proxy) }
            .onChange(of: file.id) { _, _ in revealHunk(proxy) }
            .onChange(of: isSplit) { _, _ in revealHunk(proxy) }
            .onChange(of: terminalSize) { _, _ in revealHunk(proxy) }
        }
    }
}
