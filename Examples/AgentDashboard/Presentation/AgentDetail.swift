import Chio
import SwiftTUI

@MainActor
struct AgentDetail {
    @Environment(\.chioTheme) private var theme
    let agent: Agent?
    let isCompact: Bool
    let run: @MainActor @Sendable () -> Void
    let fail: @MainActor @Sendable () -> Void
}

extension AgentDetail: View {
    var body: some View {
        GroupBox("Selected agent") {
            VStack(alignment: .leading, spacing: 1) {
                if let agent {
                    Text(agent.name).bold().foregroundStyle(theme.colors.heading)
                    if !isCompact {
                        Text(agent.summary).foregroundStyle(theme.colors.secondaryText)
                    }
                    if let progress = agent.phase.runningProgress {
                        ProgressView(value: progress.fraction, barWidth: isCompact ? 20 : 30) {
                            Text("Running test suite")
                        } currentValueLabel: {
                            Text("\(Int(progress.fraction * 100))%")
                        }
                    } else {
                        Text("\(agent.phase.symbol) \(agent.phase.label)")
                            .foregroundStyle(agent.phase.isFailed ? theme.colors.error : theme.colors.success)
                    }
                    if !isCompact {
                        Divider().foregroundStyle(theme.colors.border)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(agent.activity.enumerated()), id: \.offset) { entry in
                                Text(entry.element).foregroundStyle(theme.colors.secondaryText)
                            }
                        }
                    }
                    if !isCompact {
                        HStack(spacing: 2) {
                            Button("Run again", action: run)
                            Button("Simulate failure", action: fail)
                        }
                    }
                } else {
                    Text("Select an agent to see its activity.")
                        .foregroundStyle(theme.colors.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
