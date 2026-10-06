import SwiftTUI

struct HelpApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension HelpApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio keyboard help") { HelpExampleView(theme: theme) }
    }
}
