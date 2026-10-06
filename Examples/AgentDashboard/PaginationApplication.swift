import SwiftTUI

struct PaginationApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension PaginationApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio run history") { PaginationExampleView(theme: theme) }
    }
}
