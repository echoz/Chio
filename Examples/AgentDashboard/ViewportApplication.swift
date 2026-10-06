import SwiftTUI

struct ViewportApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension ViewportApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio activity viewport") { ViewportExampleView(theme: theme) }
    }
}
