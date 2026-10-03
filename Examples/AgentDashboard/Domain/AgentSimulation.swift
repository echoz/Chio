enum AgentSimulation {
    /// Advances sample tasks by a fixed step. Elapsed wall time is not domain state.
    static func advance(_ agents: [Agent], step: Double = 0.04) -> [Agent] {
        precondition(step.isFinite && step >= 0)
        return agents.map { agent in
            guard case .running(let progress) = agent.phase else { return agent }
            var updated = agent
            let next = min(1, progress + step)
            updated.phase = next == 1 ? .completed : .running(progress: next)
            return updated
        }
    }
}
