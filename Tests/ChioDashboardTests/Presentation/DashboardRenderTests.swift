@testable import ChioDashboard
import SwiftTUIRuntime
import Testing

@MainActor
struct DashboardRenderTests {
    @Test(arguments: [CellSize(width: 100, height: 30), CellSize(width: 100, height: 26),
                      CellSize(width: 100, height: 24), CellSize(width: 50, height: 30)])
    func normalAndNarrowDashboard(_ size: CellSize) {
        let view = DashboardView(animates: false)
        let first = DefaultRenderer().render(view, proposal: .init(width: size.width, height: size.height), frameInstant: .zero)
        let second = DefaultRenderer().render(view, proposal: .init(width: size.width, height: size.height), frameInstant: .zero)
        #expect(first.rasterSurface == second.rasterSurface)
        #expect(first.rasterSurface.size == size)
        let text = first.rasterSurface.lines.joined(separator: "\n")
        #expect(text.contains("Build Agent"))
        #expect(text.contains("Selected agent"))
        #expect(text.contains("filter"))
    }

    @Test("Short terminals retain visible selection and essential keyboard help")
    func shortDashboard() {
        let frame = DefaultRenderer().render(
            DashboardView(animates: false),
            proposal: .init(width: 36, height: 18), frameInstant: .zero
        )
        #expect(frame.rasterSurface.size == CellSize(width: 36, height: 18))
        let text = frame.rasterSurface.lines.joined(separator: "\n")
        #expect(text.contains("Build Agent"))
        #expect(text.contains("Search…"))
        #expect(text.contains("/ filter"))
        #expect(text.contains("q quit"))
    }

    @Test(arguments: [DashboardScenario.empty, .noMatches, .failed, .completed])
    func deterministicScenarios(_ scenario: DashboardScenario) {
        let frame = DefaultRenderer().render(
            DashboardView(scenario: scenario, animates: false),
            proposal: .init(width: 100, height: 30), frameInstant: .zero
        )
        let text = frame.rasterSurface.lines.joined(separator: "\n")
        switch scenario {
        case .empty: #expect(text.contains("No items yet."))
        case .noMatches: #expect(text.contains("No matches."))
        case .failed: #expect(text.contains("simulated test failed"))
        case .completed: #expect(text.contains("All checks passed"))
        case .normal: break
        }
    }
}
