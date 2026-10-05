import SwiftTUI

struct TimersApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension TimersApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio time studio") { TimerExampleView(light: light) }
    }
}
