import Chio
import SwiftTUI

@main
struct ChioDashboardCommand {
    @Flag(help: "Render a deterministic plain-text frame without an interactive terminal.")
    var snapshot = false

    @Option(help: "Snapshot width in terminal columns (20...240).")
    var width = 100

    @Option(help: "Snapshot height in terminal rows (10...100).")
    var height = 30

    @Option(help: "Sample state: normal, empty, no-matches, failed, completed.")
    var scenario: DashboardScenario = .normal

    @Flag(help: "Start with the light theme.")
    var light = false

    @Flag(help: "Start with simulated progress paused.")
    var paused = false

    @Flag(help: "Run the focused language and capability choice example.")
    var choices = false

    @OptionGroup(title: "SwiftTUI options")
    var swiftTUIOptions: SwiftTUIOptions

    @MainActor @ViewBuilder
    private var snapshotView: some View {
        if choices {
            ChoiceExampleView(light: light)
        } else {
            DashboardView(scenario: scenario, light: light, animates: false, paused: paused)
        }
    }
}

extension ChioDashboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chio-dashboard",
        abstract: "Chio — Beautiful terminal interfaces for Swift."
    )

    mutating func validate() throws {
        guard (20...240).contains(width), (10...100).contains(height) else {
            throw ValidationError("Use --width 20...240 and --height 10...100.")
        }
        if choices && (scenario != .normal || paused) {
            throw ValidationError("--scenario and --paused describe the dashboard simulation; omit them with --choices.")
        }
    }

    @MainActor
    mutating func run() async throws {
        if snapshot {
            let frame = DefaultRenderer().render(
                snapshotView.environment(\.terminalSize, .init(width: width, height: height)),
                proposal: .init(width: width, height: height),
                frameInstant: .zero
            )
            print(frame.rasterSurface.lines.joined(separator: "\n"))
        } else if choices {
            try await WebHostCLIRunner.run(ChoiceApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else {
            let app = DashboardApplication(scenario: scenario, light: light, paused: paused)
            try await WebHostCLIRunner.run(app, configuration: swiftTUIOptions.runtimeConfiguration())
        }
    }
}
