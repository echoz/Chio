import SwiftTUI

struct FormsApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension FormsApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio grouped forms") { GroupedFormExampleView(light: light) }
    }
}
