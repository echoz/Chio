import SwiftTUI

struct TabsApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension TabsApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio workspace tabs") { TabsExampleView(theme: theme) }
    }
}
