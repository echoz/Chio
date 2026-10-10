import SwiftTUI

struct DashboardApplication {
    let scenario: DashboardScenario
    let theme: ExampleTheme
    let isPaused: Bool

    nonisolated init() {
        self.init(scenario: .normal, theme: .default, isPaused: false)
    }

    nonisolated init(scenario: DashboardScenario, theme: ExampleTheme, isPaused: Bool) {
        self.scenario = scenario
        self.theme = theme
        self.isPaused = isPaused
    }
}

extension DashboardApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio") {
            DashboardView(scenario: scenario, theme: theme, shouldAnimate: true, isPaused: isPaused)
        }
    }
}
