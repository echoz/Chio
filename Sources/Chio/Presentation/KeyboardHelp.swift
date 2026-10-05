import SwiftTUIViews

/// Grouped shortcut descriptions for a native sheet or an inline help region.
/// The application owns presentation; native containers own scrolling and focus.
@MainActor
public struct KeyboardHelp {
    @Environment(\.chioTheme) private var theme
    private let groups: [ShortcutGroup]

    public init(_ groups: [ShortcutGroup]) {
        self.groups = groups
    }

    private var visibleGroups: [ShortcutGroup] {
        groups.filter { !$0.shortcuts.isEmpty }
    }
}

extension KeyboardHelp: View {
    public var body: some View {
        let visible = visibleGroups
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            if visible.isEmpty {
                Text("No keyboard shortcuts available.")
                    .foregroundStyle(theme.colors.secondaryText)
            } else {
                ForEach(visible.indices, id: \.self) { groupIndex in
                    let group = visible[groupIndex]
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.title).bold().foregroundStyle(theme.colors.heading)
                        ForEach(group.shortcuts.indices, id: \.self) { shortcutIndex in
                            let shortcut = group.shortcuts[shortcutIndex]
                            VStack(alignment: .leading, spacing: 0) {
                                KeyHint(shortcut)
                                if !shortcut.detail.isEmpty {
                                    Text(shortcut.detail).foregroundStyle(theme.colors.mutedText)
                                }
                            }
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
