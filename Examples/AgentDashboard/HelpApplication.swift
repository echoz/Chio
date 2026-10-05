import SwiftTUI

struct HelpApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension HelpApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio keyboard help") { HelpExampleView(light: light) }
    }
}
