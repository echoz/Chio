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

    /// Resolve and validate at the parser boundary, without retaining derived state.
    func resolveExample() throws -> DashboardExample {
        let hasExplicitTheme = theme != nil
        if light && hasExplicitTheme {
            throw ValidationError("Choose --theme or --light, not both.")
        }
        let isWidthSupported = (20...240).contains(width)
        let isHeightSupported = (10...100).contains(height)
        guard isWidthSupported, isHeightSupported else {
            throw ValidationError("Use --width 20...240 and --height 10...100.")
        }

        let requestedExamples: [DashboardExample] = [
            choices ? .choices : nil,
            textEntry ? .textEntry : nil,
            feedback ? .feedback : nil,
            files ? .files : nil,
            keyboardHelp ? .keyboardHelp : nil,
            tabs ? .tabs : nil,
            pagination ? .pagination : nil,
            viewport ? .viewport : nil,
            tree ? .tree : nil,
            forms ? .forms : nil,
            timers ? .timers : nil,
            metrics ? .metrics : nil,
            inbox ? .inbox : nil,
            diff ? .diff : nil,
        ].compactMap { $0 }
        guard requestedExamples.count <= 1 else {
            throw ValidationError("Choose one example: --choices, --text-entry, --feedback, --files, --keyboard-help, --tabs, --pagination, --viewport, --tree, --forms, --timers, --metrics, --inbox or --diff.")
        }
        let example = requestedExamples.first ?? .dashboard
        if example.isFocusedExample {
            let hasSimulationScenario = switch scenario {
            case .normal: false
            case .empty, .noMatches, .failed, .completed: true
            }
            let startsSimulationPaused = paused
            if hasSimulationScenario || startsSimulationPaused {
                throw ValidationError("--scenario and --paused describe the dashboard simulation; omit them with a focused example.")
            }
        }
        if directory != nil {
            guard case .files = example else {
                throw ValidationError("--directory is available only with --files.")
            }
        }
        if snapshot {
            if case .files = example {
                throw Self.fileSnapshotError
            }
        }
        return example
    }

    func resolveTheme(for example: DashboardExample) -> ExampleTheme {
        if let theme { return theme }
        if light { return .light }
        return example.defaultTheme
    }

    static var fileSnapshotError: ValidationError {
        ValidationError("--files loads folders asynchronously and does not support --snapshot; run the interactive example.")
    }
}

extension ChioDashboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chio-dashboard",
        abstract: "Chio — Beautiful terminal interfaces for Swift."
    )

    mutating func validate() throws {
        _ = try resolveExample()
    }

    @MainActor
    mutating func run() async throws {
        let example = try resolveExample()
        try await execute(example, theme: resolveTheme(for: example))
    }
}
