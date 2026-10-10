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
        case .failed: Agent.examples.map { $0.replacingPhase(.failed) }
        case .completed: Agent.examples.map { $0.replacingPhase(.completed) }
        }
    }

    var query: String {
        switch self {
        case .noMatches: "xyz"
        case .normal, .empty, .failed, .completed: ""
        }
    }

    var initialSelection: Agent.ID? {
        switch self {
        case .noMatches: nil
        case .normal, .empty, .failed, .completed: agents.first?.id
        }
    }
}

extension DashboardScenario: CaseIterable {}
extension DashboardScenario: ExpressibleByArgument {}
extension DashboardScenario: Hashable {}
extension DashboardScenario: Codable {}
extension DashboardScenario: Sendable {}
