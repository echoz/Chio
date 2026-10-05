import SwiftTUI

struct TabsApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension TabsApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio workspace tabs") { TabsExampleView(light: light) }
    }
}
