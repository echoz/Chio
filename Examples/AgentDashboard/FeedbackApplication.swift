import SwiftTUI

struct FeedbackApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension FeedbackApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio feedback") { FeedbackExampleView(theme: theme) }
    }
}
