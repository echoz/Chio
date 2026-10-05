import SwiftTUI

struct PaginationApplication {
    let light: Bool

    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension PaginationApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio run history") { PaginationExampleView(light: light) }
    }
}
