import Chio
import Foundation

/// Editable creation values. Only visible, required fields participate in validation.
struct AgentDraft {
    let name: String
    let role: Role
    let suite: String
    let startImmediately: Bool

    init(name: String = "", role: Role = .build, suite: String = "", startImmediately: Bool = true) {
        self.name = name
        self.role = role
        self.suite = suite
        self.startImmediately = startImmediately
    }

    func replacing(name: String? = nil, role: Role? = nil, suite: String? = nil,
                   startImmediately: Bool? = nil) -> AgentDraft {
        AgentDraft(name: name ?? self.name, role: role ?? self.role,
                   suite: suite ?? self.suite, startImmediately: startImmediately ?? self.startImmediately)
    }

    enum Field {
        case name
        case suite
    }

    enum Role: String {
        case build = "Build"
        case review = "Review"
        case test = "Test"
        case docs = "Docs"

        var summary: String {
            switch self {
            case .build: "Compile · resolve · package"
            case .review: "Read · inspect · suggest"
            case .test: "Check · verify · report"
            case .docs: "Write · explain · publish"
            }
        }
    }

    var issues: [FormValidation<Field>.Issue] {
        var issues: [FormValidation<Field>.Issue] = []
        if trimmedName.isEmpty {
            issues.append(.init(field: .name, message: "Enter an agent name."))
        } else if trimmedName.count > 32 {
            issues.append(.init(field: .name, message: "Use 32 characters or fewer."))
        }
        if role == .test && trimmedSuite.isEmpty {
            issues.append(.init(field: .suite, message: "Enter a test suite."))
        } else if role == .test && trimmedSuite.count > 40 {
            issues.append(.init(field: .suite, message: "Use 40 characters or fewer."))
        }
        return issues
    }

    /// The caller supplies identity; invalid drafts never become agents.
    func makeAgent(id: Agent.ID) -> Agent? {
        guard issues.isEmpty else { return nil }
        return Agent(
            id: id,
            name: trimmedName,
            summary: role == .test ? "Test suite · \(trimmedSuite)" : role.summary,
            phase: startImmediately ? .running(progress: .zero) : .idle
        )
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSuite: String { suite.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension AgentDraft: Equatable {}
extension AgentDraft: Hashable {}
extension AgentDraft: Codable {}
extension AgentDraft: Sendable {}
extension AgentDraft.Field: Hashable {}
extension AgentDraft.Field: Codable {}
extension AgentDraft.Field: Sendable {}
extension AgentDraft.Role: CaseIterable {}
extension AgentDraft.Role: Hashable {}
extension AgentDraft.Role: Codable {}
extension AgentDraft.Role: Sendable {}
