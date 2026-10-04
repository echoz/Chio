import SwiftTUI

struct DashboardApplication {
    let scenario: DashboardScenario
    let light: Bool
    let paused: Bool

    nonisolated init() {
        self.init(scenario: .normal, light: false, paused: false)
    }

    nonisolated init(scenario: DashboardScenario, light: Bool, paused: Bool) {
        self.scenario = scenario
        self.light = light
        self.paused = paused
    }
}

extension DashboardApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio") {
            DashboardView(scenario: scenario, light: light, animates: true, paused: paused)
        }
    }
}
