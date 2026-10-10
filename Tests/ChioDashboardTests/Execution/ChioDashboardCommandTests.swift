@testable import ChioDashboard
import SwiftTUI
import Testing

struct ChioDashboardCommandTests {
    private struct ExampleArguments: Sendable {
        let arguments: [String]
        let example: DashboardExample
        let startingTheme: ExampleTheme
    }

    private static let examples = [
        ExampleArguments(arguments: [], example: .dashboard, startingTheme: .default),
        ExampleArguments(arguments: ["--choices"], example: .choices, startingTheme: .default),
        ExampleArguments(arguments: ["--text-entry"], example: .textEntry, startingTheme: .default),
        ExampleArguments(arguments: ["--feedback"], example: .feedback, startingTheme: .default),
        ExampleArguments(arguments: ["--files"], example: .files, startingTheme: .default),
        ExampleArguments(arguments: ["--keyboard-help"], example: .keyboardHelp, startingTheme: .default),
        ExampleArguments(arguments: ["--tabs"], example: .tabs, startingTheme: .default),
        ExampleArguments(arguments: ["--pagination"], example: .pagination, startingTheme: .default),
        ExampleArguments(arguments: ["--viewport"], example: .viewport, startingTheme: .default),
        ExampleArguments(arguments: ["--tree"], example: .tree, startingTheme: .default),
        ExampleArguments(arguments: ["--forms"], example: .forms, startingTheme: .default),
        ExampleArguments(arguments: ["--timers"], example: .timers, startingTheme: .default),
        ExampleArguments(arguments: ["--metrics"], example: .metrics, startingTheme: .btop),
        ExampleArguments(arguments: ["--inbox"], example: .inbox, startingTheme: .default),
        ExampleArguments(arguments: ["--diff"], example: .diff, startingTheme: .default),
    ]

    private static let focusedExamples = Array(examples.dropFirst())
    private static let themeConflict = "Choose --theme or --light, not both."
    private static let dimensionError = "Use --width 20...240 and --height 10...100."
    private static let exampleConflict = "Choose one example: --choices, --text-entry, --feedback, --files, --keyboard-help, --tabs, --pagination, --viewport, --tree, --forms, --timers, --metrics, --inbox or --diff."
    private static let simulationError = "--scenario and --paused describe the dashboard simulation; omit them with a focused example."
    private static let directoryError = "--directory is available only with --files."
    private static let filesSnapshotError = "--files loads folders asynchronously and does not support --snapshot; run the interactive example."

    @Test("No arguments retain dashboard, dimensions and simulation defaults")
    func dashboardDefaults() throws {
        let command = try ChioDashboardCommand.parse([])
        #expect(try command.resolveExample() == .dashboard)
        #expect(command.width == 100)
        #expect(command.height == 30)
        #expect(command.scenario == .normal)
        #expect(!command.snapshot)
        #expect(!command.paused)
        #expect(command.directory == nil)
        #expect(command.theme == nil)
        #expect(!command.light)
    }

    @Test("Public example flags select their example and starting palette", arguments: examples)
    private func exampleDefaults(fixture: ExampleArguments) throws {
        let command = try ChioDashboardCommand.parse(fixture.arguments)
        let example = try command.resolveExample()
        #expect(example == fixture.example)
        #expect(command.resolveTheme(for: example) == fixture.startingTheme)

        let lightCommand = try ChioDashboardCommand.parse(fixture.arguments + ["--light"])
        #expect(lightCommand.resolveTheme(for: try lightCommand.resolveExample()) == .light)
    }

    @Test("Explicit themes override every example's starting palette", arguments: ExampleTheme.allCases)
    func themeOverrides(theme: ExampleTheme) throws {
        for fixture in Self.examples {
            let command = try ChioDashboardCommand.parse(fixture.arguments + ["--theme", theme.rawValue])
            #expect(command.resolveTheme(for: try command.resolveExample()) == theme)
            Self.expectRejected(fixture.arguments + ["--light", "--theme", theme.rawValue], message: Self.themeConflict)
        }
    }

    @Test("Unknown theme and scenario values retain parser diagnostics")
    func unknownValues() {
        Self.expectRejected(["--theme", "unknown"], message: "The value 'unknown' is invalid for '--theme <theme>'. Please provide one of 'default', 'light' or 'btop'.")
        Self.expectRejected(["--scenario", "unknown"], message: "The value 'unknown' is invalid for '--scenario <scenario>'. Please provide one of 'normal', 'empty', 'no-matches', 'failed' or 'completed'.")
    }

    @Test("Every pair of focused example flags is rejected")
    func conflictingExamples() {
        for firstIndex in Self.focusedExamples.indices {
            for secondIndex in Self.focusedExamples.indices where secondIndex > firstIndex {
                let arguments = Self.focusedExamples[firstIndex].arguments + Self.focusedExamples[secondIndex].arguments
                Self.expectRejected(arguments, message: Self.exampleConflict)
                Self.expectRejected(Array(arguments.reversed()), message: Self.exampleConflict)
            }
        }
    }

    @Test("Dashboard accepts every simulation scenario and paused state", arguments: DashboardScenario.allCases)
    func dashboardScenarios(scenario: DashboardScenario) throws {
        for pausedArguments in [[], ["--paused"]] {
            let command = try ChioDashboardCommand.parse(["--scenario", scenario.rawValue] + pausedArguments)
            #expect(try command.resolveExample() == .dashboard)
            #expect(command.scenario == scenario)
            #expect(command.paused == !pausedArguments.isEmpty)
        }
    }

    @Test("Focused examples accept explicit normal but reject simulation state", arguments: focusedExamples)
    private func focusedSimulationOptions(fixture: ExampleArguments) throws {
        let normalCommand = try ChioDashboardCommand.parse(fixture.arguments + ["--scenario", "normal"])
        #expect(try normalCommand.resolveExample() == fixture.example)
        Self.expectRejected(fixture.arguments + ["--paused"], message: Self.simulationError)
        Self.expectRejected(fixture.arguments + ["--scenario", "normal", "--paused"], message: Self.simulationError)
        for scenario in [DashboardScenario.empty, .noMatches, .failed, .completed] {
            Self.expectRejected(fixture.arguments + ["--scenario", scenario.rawValue], message: Self.simulationError)
        }
    }

    @Test("Directory presence is restricted to files, including an explicit empty value", arguments: ["", "/tmp/chio-cli-fixture"])
    func directories(directory: String) throws {
        let command = try ChioDashboardCommand.parse(["--files", "--directory", directory])
        #expect(try command.resolveExample() == .files)
        #expect(command.directory == directory)
        for fixture in Self.examples where fixture.example != .files {
            Self.expectRejected(fixture.arguments + ["--directory", directory], message: Self.directoryError)
        }
    }

    @Test("Snapshot accepts dashboard and synchronous focused examples but rejects files", arguments: examples)
    private func snapshotExamples(fixture: ExampleArguments) throws {
        let arguments = fixture.arguments + ["--snapshot"]
        if fixture.example == .files {
            Self.expectRejected(arguments, message: Self.filesSnapshotError)
        } else {
            let command = try ChioDashboardCommand.parse(arguments)
            #expect(try command.resolveExample() == fixture.example)
            #expect(command.snapshot)
        }
    }

    @Test("Snapshot dimension endpoints remain inclusive", arguments: [20, 240], [10, 100])
    func dimensionEndpoints(width: Int, height: Int) throws {
        let command = try ChioDashboardCommand.parse(["--snapshot", "--width", String(width), "--height", String(height)])
        #expect(command.width == width)
        #expect(command.height == height)
        #expect(try command.resolveExample() == .dashboard)
    }

    @Test("Dimensions outside either bound are rejected for snapshot and interactive launches", arguments: [
        ["--width", "19"], ["--width", "241"], ["--height", "9"], ["--height", "101"],
    ])
    func invalidDimensions(arguments: [String]) {
        Self.expectRejected(arguments, message: Self.dimensionError)
        Self.expectRejected(arguments + ["--snapshot"], message: Self.dimensionError)
    }

    @Test("Validation preserves theme, dimensions, example, simulation and directory error priority")
    func validationPriority() {
        let invalidFiles = ["--files", "--snapshot"]
        Self.expectRejected(invalidFiles + ["--directory", ""], message: Self.filesSnapshotError)
        Self.expectRejected(invalidFiles + ["--choices", "--directory", ""], message: Self.exampleConflict)
        Self.expectRejected(["--choices", "--paused", "--directory", ""], message: Self.simulationError)
        Self.expectRejected(["--snapshot", "--directory", ""], message: Self.directoryError)
        let conflictingSimulation = ["--choices", "--files", "--paused", "--directory", "", "--snapshot"]
        Self.expectRejected(conflictingSimulation + ["--width", "19"], message: Self.dimensionError)
        Self.expectRejected(conflictingSimulation + ["--width", "19", "--light", "--theme", "btop"], message: Self.themeConflict)
        Self.expectRejected(invalidFiles + ["--scenario", "failed"], message: Self.simulationError)
    }

    @Test("Native SwiftTUI flags remain flattened into the dashboard command")
    func nativeOptions() throws {
        let command = try ChioDashboardCommand.parse([
            "--choices", "--no-color", "--force-color", "--accessible", "--ascii",
            "--reduce-motion", "--stable-output", "--cursor-follows-focus", "--json",
            "--web", "--port", "9000", "--bind", "127.0.0.2", "--open", "--scene", "details", "--debug",
        ])
        #expect(try command.resolveExample() == .choices)
        let options = command.swiftTUIOptions
        #expect(options.noColor)
        #expect(options.forceColor)
        #expect(options.accessible)
        #expect(options.ascii)
        #expect(options.reduceMotion)
        #expect(options.stableOutput)
        #expect(options.cursorFollowsFocus)
        #expect(options.json)
        #expect(options.web)
        #expect(options.port == 9000)
        #expect(options.bind == "127.0.0.2")
        #expect(options.open)
        #expect(options.scene == "details")
        #expect(options.debug)
    }

    private static func expectRejected(_ arguments: [String], message: String) {
        do {
            _ = try ChioDashboardCommand.parse(arguments)
            Issue.record("Expected rejection for arguments: \(arguments)")
        } catch {
            #expect(ChioDashboardCommand.message(for: error) == message)
        }
    }
}
