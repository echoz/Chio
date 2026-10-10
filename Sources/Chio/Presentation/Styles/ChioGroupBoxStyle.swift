import SwiftTUIViews

/// Padded content with terminal chrome and an optional compact border title.
public struct ChioGroupBoxStyle {
    public let theme: ChioTheme
    public let titlePlacement: TitlePlacement

    public init(theme: ChioTheme = .default, titlePlacement: TitlePlacement = .content) {
        self.theme = theme
        self.titlePlacement = titlePlacement
    }

    public enum TitlePlacement: String {
        /// The authored heading appears above the content inside the border.
        case content
        /// A single-row, display-only heading masks part of the top border.
        /// Text truncates at the trailing edge; allocations below five cells
        /// omit its paint while retaining its authored subtree.
        case border

        var isInContent: Bool {
            switch self {
            case .content: true
            case .border: false
            }
        }

        var isOnBorder: Bool {
            switch self {
            case .content: false
            case .border: true
            }
        }
    }
}

extension ChioGroupBoxStyle: GroupBoxStyle {
    @MainActor
    public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            if titlePlacement.isInContent, let label = configuration.label {
                label.foregroundStyle(theme.colors.heading)
            }
            configuration.content
        }
        .padding(EdgeInsets(horizontal: theme.spacing.horizontalInset, vertical: theme.spacing.verticalInset))
        .foregroundStyle(theme.colors.foreground)
        .background(theme.colors.surface)
        .border(
            configuration.controlProminence == .increased ? theme.colors.accent : theme.colors.border,
            style: theme.treatments.borderStyle,
            placement: .outset
        )
        .overlay(alignment: .topLeading) {
            if titlePlacement.isOnBorder, let label = configuration.label {
                GeometryReader { geometry in
                    // Read the bordered allocation, rather than introducing a
                    // geometry container around the authored content. Keep the
                    // title mounted even when there is no room to paint it.
                    let hasTitleWidth = geometry.size.width >= 5
                    let hasTitleHeight = geometry.size.height > 0
                    label
                        .foregroundStyle(theme.colors.heading)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 1)
                        .background(theme.colors.surface)
                        .frame(width: max(0, geometry.size.width - 2), height: 1, alignment: .leading)
                        .padding(.leading, 1)
                        .frame(width: geometry.size.width, height: 1, alignment: .leading)
                        .clipped()
                        .opacity(hasTitleWidth && hasTitleHeight ? 1 : 0)
                        .disabled(true)
                        .allowsHitTesting(false)
                }
                .clipped()
            }
        }
    }
}

extension ChioGroupBoxStyle: Equatable {}

extension ChioGroupBoxStyle.TitlePlacement: Hashable {}
extension ChioGroupBoxStyle.TitlePlacement: Codable {}
extension ChioGroupBoxStyle.TitlePlacement: Sendable {}
