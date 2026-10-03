import SwiftTUI

enum DashboardScenario: String {
    case normal
    case empty
    case noMatches = "no-matches"
    case failed
    case completed

    var agents: [Agent] {
        switch self {
        case .empty: []
        case .normal, .noMatches: Agent.examples
        case .failed: Agent.examples.map { agent in
            var agent = agent
            agent.phase = .failed
            return agent
        }
        case .completed: Agent.examples.map { agent in
            var agent = agent
            agent.phase = .completed
            return agent
        }
        }
    }

    var query: String { self == .noMatches ? "xyz" : "" }
}

extension DashboardScenario: CaseIterable {}
extension DashboardScenario: ExpressibleByArgument {}
extension DashboardScenario: Sendable {}
