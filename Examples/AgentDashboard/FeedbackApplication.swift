import SwiftTUI

struct FeedbackApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension FeedbackApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio feedback") { FeedbackExampleView(light: light) }
    }
}
