import SwiftTUI

struct InboxApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension InboxApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio review inbox") { InboxExampleView(theme: theme) }
    }
}
