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

    @Option(help: "Starting theme: default, light or btop. Defaults to btop for metrics and default elsewhere.")
    var theme: ExampleTheme?

    @Flag(help: "Start with the light theme (alias for --theme light).")
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

    @Flag(help: "Run the bounded read-only diff prototype with local fixtures.")
    var diff = false

    @Option(help: "Starting folder for --files (defaults to the current working directory).")
    var directory: String?

    @OptionGroup(title: "SwiftTUI options")
    var swiftTUIOptions: SwiftTUIOptions

    var resolvedTheme: ExampleTheme { theme ?? (light ? .light : metrics ? .btop : .default) }

    @MainActor @ViewBuilder
    private var snapshotView: some View {
        if diff {
            DiffExampleView(theme: resolvedTheme)
        } else if inbox {
            InboxExampleView(theme: resolvedTheme)
        } else if metrics {
            MetricsExampleView(theme: resolvedTheme)
        } else if timers {
            TimerExampleView(theme: resolvedTheme)
        } else if forms {
            GroupedFormExampleView(theme: resolvedTheme)
        } else if tree {
            TreeExampleView(theme: resolvedTheme)
        } else if viewport {
            ViewportExampleView(theme: resolvedTheme)
        } else if pagination {
            PaginationExampleView(theme: resolvedTheme)
        } else if tabs {
            TabsExampleView(theme: resolvedTheme)
        } else if keyboardHelp {
            HelpExampleView(theme: resolvedTheme)
        } else if feedback {
            FeedbackExampleView(theme: resolvedTheme)
        } else if textEntry {
            TextEntryExampleView(theme: resolvedTheme)
        } else if choices {
            ChoiceExampleView(theme: resolvedTheme)
        } else {
            DashboardView(scenario: scenario, theme: resolvedTheme, animates: false, paused: paused)
        }
    }
}

extension ChioDashboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chio-dashboard",
        abstract: "Chio — Beautiful terminal interfaces for Swift."
    )

    mutating func validate() throws {
        if light && theme != nil {
            throw ValidationError("Choose --theme or --light, not both.")
        }
        guard (20...240).contains(width), (10...100).contains(height) else {
            throw ValidationError("Use --width 20...240 and --height 10...100.")
        }
        if [choices, textEntry, feedback, files, keyboardHelp, tabs, pagination, viewport, tree, forms, timers, metrics, inbox, diff].filter({ $0 }).count > 1 {
            throw ValidationError("Choose one example: --choices, --text-entry, --feedback, --files, --keyboard-help, --tabs, --pagination, --viewport, --tree, --forms, --timers, --metrics, --inbox or --diff.")
        }
        if (choices || textEntry || feedback || files || keyboardHelp || tabs || pagination || viewport || tree || forms || timers || metrics || inbox || diff) && (scenario != .normal || paused) {
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
        } else if diff {
            try await WebHostCLIRunner.run(DiffApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if inbox {
            try await WebHostCLIRunner.run(InboxApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if metrics {
            try await WebHostCLIRunner.run(MetricsApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if timers {
            try await WebHostCLIRunner.run(TimersApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if forms {
            try await WebHostCLIRunner.run(FormsApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if tree {
            try await WebHostCLIRunner.run(TreeApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if viewport {
            try await WebHostCLIRunner.run(ViewportApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if pagination {
            try await WebHostCLIRunner.run(PaginationApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if tabs {
            try await WebHostCLIRunner.run(TabsApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if keyboardHelp {
            try await WebHostCLIRunner.run(HelpApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if files {
            let startingDirectory = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath,
                                        isDirectory: true)
            try await WebHostCLIRunner.run(FileSelectionApplication(directory: startingDirectory, theme: resolvedTheme),
                                          configuration: swiftTUIOptions.runtimeConfiguration())
        } else if feedback {
            try await WebHostCLIRunner.run(FeedbackApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if textEntry {
            try await WebHostCLIRunner.run(TextEntryApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else if choices {
            try await WebHostCLIRunner.run(ChoiceApplication(theme: resolvedTheme), configuration: swiftTUIOptions.runtimeConfiguration())
        } else {
            let app = DashboardApplication(scenario: scenario, theme: resolvedTheme, paused: paused)
            try await WebHostCLIRunner.run(app, configuration: swiftTUIOptions.runtimeConfiguration())
        }
    }
}
