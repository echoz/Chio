import SwiftTUI

struct DiffApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension DiffApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio changes") { DiffExampleView(theme: theme) }
    }
}
