import Foundation
import SwiftTUI

struct FileSelectionApplication {
    let directory: URL
    let light: Bool

    nonisolated init() {
        directory = URL(fileURLWithPath: "/", isDirectory: true)
        light = false
    }

    nonisolated init(directory: URL, light: Bool = false) {
        self.directory = directory
        self.light = light
    }
}

extension FileSelectionApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio file selection") {
            FileSelectionExampleView(directory: directory, light: light)
        }
    }
}
