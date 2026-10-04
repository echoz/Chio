import SwiftTUIViews

/// Arranges whole hints in rows as terminal width permits.
@MainActor
public struct KeyHints<Content: View> {
    @Environment(\.chioTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

extension KeyHints: View {
    public var body: some View {
        HintFlowLayout(gap: theme.spacing.hintGap) { content }
    }
}

private struct HintFlowLayout {
    let gap: Int

    private func arrange(_ subviews: LayoutSubviews, width: Int) -> (LayoutSize, [LayoutRect]) {
        let limit = max(1, width)
        var x = 0
        var y = 0
        var rowHeight = 0
        var usedWidth = 0
        var frames: [LayoutRect] = []
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = ideal.width > limit
                ? subview.sizeThatFits(.init(width: limit, height: nil)) : ideal
            if x > 0 && x + size.width > limit {
                y += rowHeight
                x = 0
                rowHeight = 0
            }
            frames.append(.init(origin: .init(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + gap
            rowHeight = max(rowHeight, size.height)
        }
        return (.init(width: usedWidth, height: y + rowHeight), frames)
    }
}

extension HintFlowLayout: Layout {
    // The gap is this layout's only value input. SwiftTUI separately validates
    // the proposal and child dependencies before reusing native layout work.
    var measurementReuseSignature: String? { "Chio.HintFlowLayout:gap=\(gap)" }
    var placementReuseSignature: String? { measurementReuseSignature }

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> LayoutSize {
        let width: Int
        if case .finite(let value) = proposal.width { width = value }
        else { width = .max }
        return arrange(subviews, width: width).0
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) {
        let frames = arrange(subviews, width: bounds.size.width).1
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: .init(x: bounds.origin.x + frame.origin.x, y: bounds.origin.y + frame.origin.y),
                proposal: .init(width: frame.size.width, height: frame.size.height)
            )
        }
    }
}
