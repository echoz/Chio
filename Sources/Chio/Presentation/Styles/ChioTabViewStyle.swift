import SwiftTUIViews

/// A compact native tab strip with distinct selection and keyboard-focus paint.
public struct ChioTabViewStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioTabViewStyle: TabViewStyle {
    @MainActor
    public func presentation(for configuration: TabViewStyleConfiguration) -> TabViewStylePresentation {
        let widths = configuration.options.map { tabWidth($0.label.displayText) }
        let available = max(0, configuration.availableWidth)
        if widths.reduce(0, +) <= available {
            return .init(stripHeight: 2, visibleOptionIndices: Array(widths.indices), overflowMenu: nil)
        }

        let triggerLabel = configuration.isOverflowMenuExpanded ? "More ▴" : "More ▾"
        let limit = max(0, available - tabWidth(triggerLabel))
        var leadingWidth = 0
        var visible: [Int] = []
        for index in widths.indices {
            guard widths[index] <= limit - leadingWidth else { break }
            visible.append(index)
            leadingWidth += widths[index]
        }
        let overflow = Array(widths.indices.dropFirst(visible.count))
        return .init(
            stripHeight: 2,
            visibleOptionIndices: visible,
            overflowMenu: .init(
                triggerLeadingWidth: leadingWidth,
                overflowIndices: overflow,
                isExpanded: configuration.isOverflowMenuExpanded,
                selectedOverflowIndex: configuration.selectedIndex.flatMap { overflow.contains($0) ? $0 : nil },
                focusedOverflowIndex: configuration.focusedIndex.flatMap { overflow.contains($0) ? $0 : nil },
                triggerLabel: triggerLabel,
                backgroundStyle: AnyShapeStyle(theme.colors.surface),
                borderStyle: AnyShapeStyle(theme.colors.border),
                borderInset: 1
            )
        )
    }

    @MainActor
    public func makeBody(configuration: TabViewStyleBodyConfiguration) -> some View {
        ChioTabViewBody(configuration: configuration, theme: theme)
    }

    private func tabWidth(_ label: String) -> Int {
        layoutText(for: label, width: nil).size.width + 2
    }
}

extension ChioTabViewStyle: Equatable {}

@MainActor
private struct ChioTabViewBody {
    let configuration: TabViewStyleBodyConfiguration
    let theme: ChioTheme
    @Environment(\.isEnabled) private var isEnabled

    private func stripLabel(_ label: String, selected: Bool, focused: Bool, width: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: " " + label + " ")
                .bold(selected)
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width, height: 1, alignment: .leading)
                .background(focused && isEnabled ? theme.colors.selectedSurface : theme.colors.surface)
            Text(verbatim: String(repeating: selected ? "━" : "─", count: width))
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.border)
                .frame(width: width, height: 1, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func menuWidth(available: Int) -> Int {
        min(max(0, available),
            (configuration.overflowItems.map { layoutText(for: $0.label.displayText, width: nil).size.width }.max() ?? 0) + 4)
    }

    private func menuStart(height: Int) -> Int {
        // Focus paint may be suppressed, but the native cursor must still be revealed.
        let index = configuration.focusedIndex ?? configuration.selectedIndex
        let position = configuration.overflowItems.firstIndex { $0.index == index } ?? 0
        return min(max(0, position - height + 1), max(0, configuration.overflowItems.count - height))
    }

    private func overflowMenu(width: Int, height: Int) -> some View {
        ScrollView(.vertical, position: .constant(ScrollCellOffset(x: 0, y: menuStart(height: height)))) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(configuration.overflowItems, id: \.index) { item in
                    item.overflowRoute {
                        Text(verbatim: (item.isSelected ? theme.treatments.selectionMarker : " ") + " " + item.label.displayText)
                            .bold(item.isSelected)
                            .foregroundStyle(item.isSelected ? theme.colors.accent : theme.colors.foreground)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: width - 2, height: 1, alignment: .leading)
                            .background(item.isFocused && isEnabled ? theme.colors.selectedSurface : theme.colors.surface)
                    }
                }
            }
        }
        .focusable(false)
        .scrollIndicators(.hidden)
        .frame(width: width - 2, height: height)
        .padding(1)
        .background(theme.colors.surface)
        .border(theme.colors.border, style: theme.treatments.borderStyle)
        .frame(width: width, height: height + 2)
    }
}

extension ChioTabViewBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(configuration.visibleItems, id: \.index) { item in
                    item.route {
                        stripLabel(item.label.displayText, selected: item.isSelected, focused: item.isFocused,
                                   width: layoutText(for: item.label.displayText, width: nil).size.width + 2)
                    }
                }
                if let trigger = configuration.overflowTrigger, configuration.availableWidth > 0 {
                    trigger.route {
                        stripLabel(trigger.label, selected: trigger.isSelected,
                                   focused: trigger.isFocused && configuration.showsFocusEffect,
                                   width: min(configuration.availableWidth,
                                              layoutText(for: trigger.label, width: nil).size.width + 2))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: configuration.presentation.stripHeight, alignment: .leading)
            configuration.content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if configuration.overflowTrigger?.isExpanded == true {
                GeometryReader { geometry in
                    let availableRows = geometry.size.height - configuration.presentation.stripHeight - 2
                    let availableWidth = min(geometry.size.width, configuration.availableWidth)
                    let width = menuWidth(available: availableWidth)
                    let leading = min(configuration.overflowTrigger?.leadingWidth ?? 0, max(0, availableWidth - width))
                    // A bordered row needs two border cells and at least one content cell.
                    if availableRows > 0, width >= 3 {
                        overflowMenu(width: width, height: min(configuration.overflowItems.count, availableRows))
                            .padding(.init(top: configuration.presentation.stripHeight, leading: leading,
                                           bottom: 0, trailing: 0))
                    }
                }
            }
        }
        .clipped()
        .opacity(isEnabled ? 1 : 0.6)
    }
}
