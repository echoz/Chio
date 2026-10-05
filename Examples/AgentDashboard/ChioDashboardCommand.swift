import Chio
import Foundation
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

    @Flag(help: "Run the focused password and multiline text-entry example.")
    var textEntry = false

    @Flag(help: "Run the focused confirmation, spinner and toast example.")
    var feedback = false

    @Flag(help: "Run the focused filesystem file-selection example.")
    var files = false

    @Flag(help: "Run the focused contextual keyboard-help example.")
    var keyboardHelp = false

    @Flag(help: "Run the focused workspace tabs example.")
    var tabs = false

    @Flag(help: "Run the focused paginated history example.")
    var pagination = false

    @Flag(help: "Run the focused two-axis scrolling example.")
    var viewport = false

    @Flag(help: "Run the focused expandable project-tree example.")
    var tree = false

    @Flag(help: "Run the focused grouped settings form example.")
    var forms = false

    @Flag(help: "Run the focused stopwatch and countdown example.")
    var timers = false

    @Flag(help: "Run the compact metrics and passive history example.")
    var metrics = false

    @Flag(help: "Run the local review inbox and Markdown preview example.")
    var inbox = false

    @Option(help: "Starting folder for --files (defaults to the current working directory).")
    var directory: String?

    @OptionGroup(title: "SwiftTUI options")
    var swiftTUIOptions: SwiftTUIOptions

    @MainActor @ViewBuilder
    private var snapshotView: some View {
        if inbox {
            InboxExampleView(light: light)
        } else if metrics {
            MetricsExampleView(light: light)
        } else if timers {
            TimerExampleView(light: light)
        } else if forms {
            GroupedFormExampleView(light: light)
        } else if tree {
            TreeExampleView(light: light)
        } else if viewport {
            ViewportExampleView(light: light)
        } else if pagination {
            PaginationExampleView(light: light)
        } else if tabs {
            TabsExampleView(light: light)
        } else if keyboardHelp {
            HelpExampleView(light: light)
        } else if feedback {
            FeedbackExampleView(light: light)
        } else if textEntry {
            TextEntryExampleView(light: light)
        } else if choices {
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
        if [choices, textEntry, feedback, files, keyboardHelp, tabs, pagination, viewport, tree, forms, timers, metrics, inbox].filter({ $0 }).count > 1 {
            throw ValidationError("Choose one example: --choices, --text-entry, --feedback, --files, --keyboard-help, --tabs, --pagination, --viewport, --tree, --forms, --timers, --metrics or --inbox.")
        }
        if (choices || textEntry || feedback || files || keyboardHelp || tabs || pagination || viewport || tree || forms || timers || metrics || inbox) && (scenario != .normal || paused) {
            throw ValidationError("--scenario and --paused describe the dashboard simulation; omit them with a focused example.")
        }
        if directory != nil && !files {
            throw ValidationError("--directory is available only with --files.")
        }
        if files && snapshot {
            throw ValidationError("--files loads folders asynchronously and does not support --snapshot; run the interactive example.")
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
        } else if inbox {
            try await WebHostCLIRunner.run(InboxApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if metrics {
            try await WebHostCLIRunner.run(MetricsApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if timers {
            try await WebHostCLIRunner.run(TimersApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if forms {
            try await WebHostCLIRunner.run(FormsApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if tree {
            try await WebHostCLIRunner.run(TreeApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if viewport {
            try await WebHostCLIRunner.run(ViewportApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if pagination {
            try await WebHostCLIRunner.run(PaginationApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if tabs {
            try await WebHostCLIRunner.run(TabsApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if keyboardHelp {
            try await WebHostCLIRunner.run(HelpApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if files {
            let startingDirectory = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath,
                                        isDirectory: true)
            try await WebHostCLIRunner.run(FileSelectionApplication(directory: startingDirectory, light: light),
                                          configuration: swiftTUIOptions.runtimeConfiguration())
        } else if feedback {
            try await WebHostCLIRunner.run(FeedbackApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if textEntry {
            try await WebHostCLIRunner.run(TextEntryApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if choices {
            try await WebHostCLIRunner.run(ChoiceApplication(light: light), configuration: swiftTUIOptions.runtimeConfiguration())
        } else {
            let app = DashboardApplication(scenario: scenario, light: light, paused: paused)
            try await WebHostCLIRunner.run(app, configuration: swiftTUIOptions.runtimeConfiguration())
        }
    }
}
