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

    var query: String { self == .noMatches ? "xyz" : "" }
}

extension DashboardScenario: CaseIterable {}
extension DashboardScenario: ExpressibleByArgument {}
extension DashboardScenario: Hashable {}
extension DashboardScenario: Codable {}
extension DashboardScenario: Sendable {}
