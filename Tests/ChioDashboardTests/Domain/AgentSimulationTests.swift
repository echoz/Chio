@testable import ChioDashboard
import Testing

struct AgentSimulationTests {
    @Test func advancesOnlyRunningAgents() {
        let advanced = AgentSimulation.advance(Agent.examples, step: 0.1)
        #expect(advanced.map(\.id) == Agent.examples.map(\.id))
        #expect(advanced[0].phase == .running(progress: 0.88))
        #expect(Array(advanced.dropFirst()) == Array(Agent.examples.dropFirst()))
    }

    @Test func finishesAtTheProgressBoundary() {
        let finished = AgentSimulation.advance(Agent.examples, step: 0.3)
        #expect(finished[0].phase == .completed)
        #expect(AgentSimulation.advance(finished) == finished)
    }

    @Test func emptySimulationStaysEmpty() {
        #expect(AgentSimulation.advance([]).isEmpty)
    }
}
