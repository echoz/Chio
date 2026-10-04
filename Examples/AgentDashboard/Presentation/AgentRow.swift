import Chio
import SwiftTUI

@MainActor
struct AgentRow {
    @Environment(\.chioTheme) private var theme
    let agent: Agent
    let compact: Bool

    init(agent: Agent, compact: Bool = false) {
        self.agent = agent
        self.compact = compact
    }

    private var statusColor: Color {
        switch agent.phase {
        case .idle: theme.colors.mutedText
        case .running: theme.colors.accent
        case .completed: theme.colors.success
        case .failed: theme.colors.error
        }
    }
}

extension AgentRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text(agent.phase.symbol).foregroundStyle(statusColor)
                Text(agent.name).bold()
                Spacer()
                Text(agent.phase.label).foregroundStyle(statusColor)
            }
            if !compact {
                Text(agent.summary).foregroundStyle(theme.colors.secondaryText)
            }
        }
        .padding(.bottom, compact ? 0 : 1)
    }
}
