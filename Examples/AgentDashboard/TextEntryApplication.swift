import SwiftTUI

struct TextEntryApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension TextEntryApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio text entry") {
            TextEntryExampleView(light: light)
        }
    }
}
