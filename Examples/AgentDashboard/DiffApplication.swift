import SwiftTUI

struct DiffApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension DiffApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio changes") { DiffExampleView(light: light) }
    }
}
