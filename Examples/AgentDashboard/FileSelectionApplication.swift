import Foundation
import SwiftTUI

struct FileSelectionApplication {
    let directory: URL
    let theme: ExampleTheme

    nonisolated init() {
        directory = URL(fileURLWithPath: "/", isDirectory: true)
        theme = .default
    }

    nonisolated init(directory: URL, theme: ExampleTheme = .default) {
        self.directory = directory
        self.theme = theme
    }
}

extension FileSelectionApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio file selection") {
            FileSelectionExampleView(directory: directory, theme: theme)
        }
    }
}
