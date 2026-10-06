import SwiftTUI

struct DashboardApplication {
    let scenario: DashboardScenario
    let theme: ExampleTheme
    let paused: Bool

    nonisolated init() {
        self.init(scenario: .normal, theme: .default, paused: false)
    }

    nonisolated init(scenario: DashboardScenario, theme: ExampleTheme, paused: Bool) {
        self.scenario = scenario
        self.theme = theme
        self.paused = paused
    }
}

extension DashboardApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio") {
            DashboardView(scenario: scenario, theme: theme, animates: true, paused: paused)
        }
    }
}
