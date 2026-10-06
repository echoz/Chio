import SwiftTUI

struct MetricsApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .btop }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension MetricsApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio metrics studio") { MetricsExampleView(theme: theme) }
    }
}
