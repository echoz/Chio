import SwiftTUI

struct TreeApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension TreeApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio project tree") { TreeExampleView(light: light) }
    }
}
