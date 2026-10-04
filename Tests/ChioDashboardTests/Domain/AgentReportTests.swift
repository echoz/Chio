@testable import ChioDashboard
import Testing

struct AgentReportTests {
    @Test("A report keeps its captured run after simulation advances and finishes")
    func immutableRunSnapshot() {
        let agent = Agent.examples[0]
        let report = AgentReport(agent: agent)
        let sameSnapshot = AgentReport(agent: agent)
        let advanced = AgentSimulation.advance([agent], step: 0.1)[0]
        let completed = AgentSimulation.advance([advanced], step: 1)[0]

        #expect(report == sameSnapshot)
        #expect(report.agent == agent)
        #expect(report.agent.phase == .running(progress: 0.78))
        #expect(completed.phase == .completed)
        #expect(report != AgentReport(agent: advanced))
        #expect(report.document != AgentReport(agent: advanced).document)
        #expect(report.document != AgentReport(agent: completed).document)
        #expect(report == sameSnapshot)
    }
}
