struct Agent {
    let id: String
    let name: String
    let summary: String
    var phase: Phase

    enum Phase {
        case idle
        case running(progress: Double)
        case completed
        case failed

        var label: String {
            switch self {
            case .idle: "Idle"
            case .running: "Running"
            case .completed: "Complete"
            case .failed: "Failed"
            }
        }

        var symbol: String {
            switch self {
            case .idle: "○"
            case .running: "●"
            case .completed: "✓"
            case .failed: "!"
            }
        }
    }

    var activity: [String] {
        switch phase {
        case .idle:
            ["Ready when you are.", "Run this agent to start a simulated task."]
        case .running(let progress):
            ["✓ Prepared the workspace", "✓ Resolved dependencies",
             progress < 0.5 ? "› Compiling the package…" : "✓ Compiled the package",
             progress < 0.5 ? "  Tests queued" : "› Running the test suite…"]
        case .completed:
            ["✓ Prepared the workspace", "✓ Compiled the package", "✓ All checks passed", "Finished. Your terminal looks chio."]
        case .failed:
            ["✓ Prepared the workspace", "✓ Compiled the package", "! A simulated test failed", "Run again to try a successful task."]
        }
    }

    static let examples: [Agent] = [
        .init(id: "build", name: "Build Agent", summary: "Compile · resolve · package", phase: .running(progress: 0.78)),
        .init(id: "review", name: "Review Agent", summary: "Read · inspect · suggest", phase: .idle),
        .init(id: "test", name: "Test Agent", summary: "Check · verify · report", phase: .failed),
        .init(id: "docs", name: "Docs Agent", summary: "Write · explain · publish", phase: .completed),
    ]
}

extension Agent: Identifiable {}
extension Agent: Equatable {}
extension Agent: Sendable {}
extension Agent.Phase: Equatable {}
extension Agent.Phase: Sendable {}
