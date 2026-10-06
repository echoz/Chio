import Chio
import SwiftTUI

/// An example-only proof of paired source rows over native text and layout.
@MainActor
struct DiffFileView {
    let file: DiffFile
    let split: Bool
    let minimumWidth: Int
    let sourceWidth: Int
    let activeHunk: Int?
    @Environment(\.chioTheme) private var theme

    struct HunkAnchor {
        let fileID: String
        let index: Int
    }

    private var gutterWidth: Int {
        let last = file.hunks.map { max($0.oldOffset + $0.oldCount, $0.newOffset + $0.newCount) }.max() ?? 0
        return max(2, String(last).count)
    }

    private var paneWidth: Int { max(gutterWidth + 3 + sourceWidth, (minimumWidth - 3) / 2) }
    private var contentWidth: Int {
        split ? paneWidth * 2 + 3 : max(minimumWidth, gutterWidth * 2 + 4 + sourceWidth)
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .foregroundStyle(theme.colors.mutedText)
            .frame(width: gutterWidth, alignment: .trailing)
    }

    private func ink(for marker: String) -> Color {
        // Change ink is independent of success/error status. Palette decisions
        // remain in this prototype until a public diff style earns its contract.
        marker == "+" ? theme.syntax.string
            : marker == "−" ? theme.colors.accent : theme.colors.foreground
    }

    private func unifiedRow(_ row: DiffFile.UnifiedRow) -> some View {
        let old: DiffFile.Line?
        let new: DiffFile.Line?
        let text: String
        let marker: String
        switch row {
        case .context(let before, let after): (old, new, text, marker) = (before, after, before.text, " ")
        case .removed(let line): (old, new, text, marker) = (line, nil, line.text, "−")
        case .added(let line): (old, new, text, marker) = (nil, line, line.text, "+")
        }
        return HStack(spacing: 1) {
            gutter(old?.number)
            gutter(new?.number)
            Text(marker).foregroundStyle(ink(for: marker))
            Text(verbatim: text).fixedSize().foregroundStyle(ink(for: marker))
        }
        .frame(width: contentWidth, height: 1, alignment: .leading)
    }

    private func pane(_ line: DiffFile.Line?, marker: String) -> some View {
        let displayedMarker = line == nil ? " " : marker
        return HStack(spacing: 1) {
            gutter(line?.number)
            Text(displayedMarker).foregroundStyle(ink(for: displayedMarker))
            Text(verbatim: line?.text ?? "").fixedSize().foregroundStyle(ink(for: displayedMarker))
        }
        .frame(width: paneWidth, height: 1, alignment: .leading)
    }

    private func splitRow(_ row: DiffFile.SplitRow) -> some View {
        let old: DiffFile.Line?
        let new: DiffFile.Line?
        let changed: Bool
        switch row {
        case .context(let before, let after): (old, new, changed) = (before, after, false)
        case .replacement(let before, let after): (old, new, changed) = (before, after, true)
        case .removed(let line): (old, new, changed) = (line, nil, true)
        case .added(let line): (old, new, changed) = (nil, line, true)
        }
        return HStack(spacing: 1) {
            pane(old, marker: changed ? "−" : " ")
            Text("│").foregroundStyle(theme.colors.border)
            pane(new, marker: changed ? "+" : " ")
        }
    }

    private var summary: String {
        if case .binary = file.content { return "Binary content · no source lines to display." }
        switch file.change {
        case .added: return "Empty file added."
        case .deleted: return "Empty file deleted."
        case .renamed(let before, _): return "Renamed from \(before). No textual changes."
        case .modified: return "No textual changes."
        }
    }
}

extension DiffFileView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if file.hunks.isEmpty {
                Text(summary).foregroundStyle(theme.colors.secondaryText).fixedSize()
            } else {
                if split {
                    HStack(spacing: 1) {
                        Text("BEFORE").frame(width: paneWidth, alignment: .leading)
                        Text("│")
                        Text("AFTER").frame(width: paneWidth, alignment: .leading)
                    }
                    .foregroundStyle(theme.colors.mutedText)
                }
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { index, hunk in
                    Text("\(hunk.header)  · hunk \(index + 1)")
                        .foregroundStyle(theme.colors.heading)
                        .frame(width: contentWidth, height: 1, alignment: .leading)
                        .background(index == activeHunk ? theme.colors.selectedSurface : theme.colors.surface)
                        .id(HunkAnchor(fileID: file.id, index: index))
                    if split {
                        ForEach(Array(hunk.splitRows.enumerated()), id: \.offset) { _, row in splitRow(row) }
                    } else {
                        ForEach(Array(hunk.unifiedRows.enumerated()), id: \.offset) { _, row in unifiedRow(row) }
                    }
                    Text("").frame(height: 1)
                }
            }
        }
        .fixedSize()
    }
}

extension DiffFileView.HunkAnchor: Hashable {}
extension DiffFileView.HunkAnchor: Sendable {}

// SwiftTUI validates environment dependencies before reusing an equal view.
extension DiffFileView: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.file == rhs.file && lhs.split == rhs.split
            && lhs.minimumWidth == rhs.minimumWidth && lhs.sourceWidth == rhs.sourceWidth
            && lhs.activeHunk == rhs.activeHunk
    }
}
