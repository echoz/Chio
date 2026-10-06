import SwiftTUI

struct ChoiceApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension ChoiceApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio choices") {
            ChoiceExampleView(theme: theme)
        }
    }
}
