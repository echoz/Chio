@testable import ChioDashboard
import Foundation
import Testing

struct AgentTests {
    @Test("Running progress rejects nonfinite values and values outside an unfinished run",
          arguments: [Double.nan, .infinity, -.infinity, -0.1, 1, 1.1])
    func invalidProgress(_ fraction: Double) {
        #expect(Agent.RunningProgress(fraction: fraction) == nil)
    }

    @Test("Running progress includes zero and finite fractions below completion",
          arguments: [0.0, 0.5, 1.0.nextDown])
    func validProgress(_ fraction: Double) throws {
        let progress = try #require(Agent.RunningProgress(fraction: fraction))
        #expect(progress.fraction == fraction)
        #expect(Agent.RunningProgress.zero.fraction == 0)
        let data = try JSONEncoder().encode(progress)
        #expect(try JSONDecoder().decode(Agent.RunningProgress.self, from: data) == progress)
    }

    @Test("Decoding enforces running progress even when the decoder accepts nonfinite numbers",
          arguments: [Double.nan, .infinity, -.infinity, -0.1, 1, 1.1])
    func invalidProgressDecoding(_ fraction: Double) throws {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        let data = try encoder.encode(ProgressPayload(fraction: fraction))
        #expect(throws: DecodingError.self) {
            try decoder.decode(Agent.RunningProgress.self, from: data)
        }
    }

    @Test("An enclosing agent cannot decode invalid running progress")
    func invalidAgentDecoding() throws {
        let data = Data(#"{"id":"invalid","name":"Agent","summary":"Demo","phase":{"running":{"progress":{"fraction":1}}}}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Agent.self, from: data)
        }
    }

    @Test("Phase replacement preserves identity and metadata without changing the original")
    func phaseReplacement() {
        let original = Agent.examples[0]
        let updated = original.replacingPhase(.failed)
        #expect(updated.id == original.id)
        #expect(updated.name == original.name)
        #expect(updated.summary == original.summary)
        #expect(updated.phase == .failed)
        #expect(original.phase == .running(progress: Agent.RunningProgress(fraction: 0.78)!))
    }

    @Test("Agents and scenarios preserve their values through synthesized codecs")
    func modelCodecs() throws {
        let agents = Agent.examples + [Agent.examples[0].replacingPhase(.running(progress: .zero))]
        let decoded = try JSONDecoder().decode([Agent].self, from: JSONEncoder().encode(agents))
        #expect(decoded == agents)
        #expect(Set(decoded) == Set(agents))
        for scenario in DashboardScenario.allCases {
            let data = try JSONEncoder().encode(scenario)
            #expect(try JSONDecoder().decode(DashboardScenario.self, from: data) == scenario)
        }
    }

    private struct ProgressPayload: Encodable {
        let fraction: Double
    }
}
