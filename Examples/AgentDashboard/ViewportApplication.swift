import SwiftTUI

struct ViewportApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension ViewportApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio activity viewport") { ViewportExampleView(light: light) }
    }
}
