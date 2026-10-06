import SwiftTUI

struct FormsApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension FormsApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio grouped forms") { GroupedFormExampleView(theme: theme) }
    }
}
