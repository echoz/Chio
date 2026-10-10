struct Agent {
    let id: String
    let name: String
    let summary: String
    let phase: Phase

    func replacingPhase(_ phase: Phase) -> Agent {
        Agent(id: id, name: name, summary: summary, phase: phase)
    }

    /// A finite fraction of an unfinished run; completion is a separate phase.
    struct RunningProgress {
        let fraction: Double

        init?(fraction: Double) {
            guard fraction.isFinite, (0..<1).contains(fraction) else { return nil }
            self.fraction = fraction
        }

        static let zero = RunningProgress(fraction: 0)!
    }

    enum Phase {
        case idle
        case running(progress: RunningProgress)
        case completed
        case failed

        var runningProgress: RunningProgress? {
            switch self {
            case .running(let progress): progress
            case .idle, .completed, .failed: nil
            }
        }

        var isFailed: Bool {
            switch self {
            case .failed: true
            case .idle, .running, .completed: false
            }
        }

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
             progress.fraction < 0.5 ? "› Compiling the package…" : "✓ Compiled the package",
             progress.fraction < 0.5 ? "  Tests queued" : "› Running the test suite…"]
        case .completed:
            ["✓ Prepared the workspace", "✓ Compiled the package", "✓ All checks passed", "Finished. Your terminal looks chio."]
        case .failed:
            ["✓ Prepared the workspace", "✓ Compiled the package", "! A simulated test failed", "Run again to try a successful task."]
        }
    }

    static let examples: [Agent] = [
        Agent(id: "build", name: "Build Agent", summary: "Compile · resolve · package", phase: .running(progress: RunningProgress(fraction: 0.78)!)),
        Agent(id: "review", name: "Review Agent", summary: "Read · inspect · suggest", phase: .idle),
        Agent(id: "test", name: "Test Agent", summary: "Check · verify · report", phase: .failed),
        Agent(id: "docs", name: "Docs Agent", summary: "Write · explain · publish", phase: .completed),
    ]
}

extension Agent: Identifiable {}
extension Agent: Equatable {}
extension Agent: Hashable {}
extension Agent: Codable {}
extension Agent: Sendable {}
extension Agent.Phase: Equatable {}
extension Agent.Phase: Hashable {}
extension Agent.Phase: Codable {}
extension Agent.Phase: Sendable {}
extension Agent.RunningProgress: Equatable {}
extension Agent.RunningProgress: Hashable {}
extension Agent.RunningProgress: Sendable {}

extension Agent.RunningProgress: Codable {
    private enum CodingKeys: String, CodingKey { case fraction }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fraction = try container.decode(Double.self, forKey: .fraction)
        guard let progress = Agent.RunningProgress(fraction: fraction) else {
            throw DecodingError.dataCorruptedError(
                forKey: .fraction, in: container,
                debugDescription: "Running progress must be finite and in 0..<1."
            )
        }
        self = progress
    }
}
