import SwiftTUI

struct TimersApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension TimersApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio time studio") { TimerExampleView(theme: theme) }
    }
}
