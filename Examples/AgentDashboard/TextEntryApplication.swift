import SwiftTUI

struct TextEntryApplication {
    let theme: ExampleTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ExampleTheme) { self.theme = theme }
}

extension TextEntryApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio text entry") {
            TextEntryExampleView(theme: theme)
        }
    }
}
