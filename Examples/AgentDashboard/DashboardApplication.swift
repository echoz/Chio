import SwiftTUI

struct DashboardApplication {
    var scenario: DashboardScenario = .normal
    var light = false
    var paused = false
}

extension DashboardApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio") {
            DashboardView(scenario: scenario, light: light, animates: true, paused: paused)
        }
    }
}
