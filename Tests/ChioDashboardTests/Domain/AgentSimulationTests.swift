@testable import ChioDashboard
import Testing

struct AgentSimulationTests {
    @Test func advancesOnlyRunningAgents() {
        let original = Agent.examples
        let advanced = AgentSimulation.advance(original, step: 0.1)
        #expect(advanced.map(\.id) == original.map(\.id))
        #expect(advanced[0].phase == .running(progress: Agent.RunningProgress(fraction: 0.88)!))
        #expect(Array(advanced.dropFirst()) == Array(original.dropFirst()))
        #expect(original[0].phase == .running(progress: Agent.RunningProgress(fraction: 0.78)!))
    }

    @Test func finishesAtTheProgressBoundary() {
        let finished = AgentSimulation.advance(Agent.examples, step: 0.3)
        #expect(finished[0].phase == .completed)
        #expect(AgentSimulation.advance(finished) == finished)
    }

    @Test func emptySimulationStaysEmpty() {
        #expect(AgentSimulation.advance([]).isEmpty)
    }

    @Test("Zero-step advancement preserves running values and large finite steps complete")
    func stepBoundaries() {
        let original = Agent.examples
        #expect(AgentSimulation.advance(original, step: 0) == original)
        #expect(AgentSimulation.advance(original, step: .greatestFiniteMagnitude)[0].phase == .completed)
        #expect(original[0].phase == .running(progress: Agent.RunningProgress(fraction: 0.78)!))
    }
}
