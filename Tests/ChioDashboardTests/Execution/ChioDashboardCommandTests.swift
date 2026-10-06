@testable import ChioDashboard
import SwiftTUI
import Testing

struct ChioDashboardCommandTests {
    @Test("Omitted theme retains each example's starting palette and the light alias")
    func defaults() throws {
        #expect(try ChioDashboardCommand.parse([]).resolvedTheme == .default)
        #expect(try ChioDashboardCommand.parse(["--metrics"]).resolvedTheme == .btop)
        #expect(try ChioDashboardCommand.parse(["--light"]).resolvedTheme == .light)
        #expect(try ChioDashboardCommand.parse(["--metrics", "--light"]).resolvedTheme == .light)
    }

    @Test("Explicit themes override every example's starting palette", arguments: ExampleTheme.allCases)
    func overrides(theme: ExampleTheme) throws {
        for example in [[], ["--choices"], ["--text-entry"], ["--feedback"], ["--files"],
                        ["--keyboard-help"], ["--tabs"], ["--pagination"], ["--viewport"],
                        ["--tree"], ["--forms"], ["--timers"], ["--metrics"], ["--inbox"], ["--diff"]] {
            let command = try ChioDashboardCommand.parse(example + ["--theme", theme.rawValue])
            #expect(command.resolvedTheme == theme)
        }
    }

    @Test("Unknown and conflicting theme choices are rejected")
    func invalidArguments() throws {
        #expect(throws: (any Error).self) { try ChioDashboardCommand.parse(["--theme", "unknown"]) }
        #expect(throws: (any Error).self) { try ChioDashboardCommand.parse(["--light", "--theme", "btop"]) }
    }
}
