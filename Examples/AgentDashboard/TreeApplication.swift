import SwiftTUI

struct TreeApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension TreeApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio project tree") { TreeExampleView(theme: theme) }
    }
}
