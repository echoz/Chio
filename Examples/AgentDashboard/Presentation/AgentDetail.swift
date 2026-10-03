import Chio
import SwiftTUI

@MainActor
struct AgentDetail {
    @Environment(\.chioTheme) private var theme
    let agent: Agent?
    let compact: Bool
    let run: @MainActor @Sendable () -> Void
    let fail: @MainActor @Sendable () -> Void
}

extension AgentDetail: View {
    var body: some View {
        GroupBox("Selected agent") {
            VStack(alignment: .leading, spacing: 1) {
                if let agent {
                    Text(agent.name).bold().foregroundStyle(theme.colors.heading)
                    if !compact {
                        Text(agent.summary).foregroundStyle(theme.colors.secondaryText)
                    }
                    if case .running(let progress) = agent.phase {
                        ProgressView(value: progress, barWidth: compact ? 20 : 30) {
                            Text("Running test suite")
                        } currentValueLabel: {
                            Text("\(Int(progress * 100))%")
                        }
                    } else {
                        Text("\(agent.phase.symbol) \(agent.phase.label)")
                            .foregroundStyle(agent.phase == .failed ? theme.colors.error : theme.colors.success)
                    }
                    if !compact {
                        Divider().foregroundStyle(theme.colors.border)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(agent.activity.enumerated()), id: \.offset) { entry in
                                Text(entry.element).foregroundStyle(theme.colors.secondaryText)
                            }
                        }
                    }
                    if !compact {
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
