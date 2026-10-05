import SwiftTUI

struct InboxApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension InboxApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio review inbox") { InboxExampleView(light: light) }
    }
}
