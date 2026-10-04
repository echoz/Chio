import SwiftTUI

struct ChoiceApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension ChoiceApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio choices") {
            ChoiceExampleView(light: light)
        }
    }
}
