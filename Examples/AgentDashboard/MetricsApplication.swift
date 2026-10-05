import SwiftTUI

struct MetricsApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension MetricsApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio metrics studio") { MetricsExampleView(light: light) }
    }
}
