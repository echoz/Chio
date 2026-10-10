import Foundation
import SwiftTUI

extension ChioDashboardCommand {
    @MainActor
    func execute(_ example: DashboardExample, theme: ExampleTheme) async throws {
        if snapshot {
            print(try renderSnapshot(example, theme: theme))
            return
        }

        let configuration = swiftTUIOptions.runtimeConfiguration()
        switch example {
        case .dashboard:
            let app = DashboardApplication(scenario: scenario, theme: theme, isPaused: paused)
            try await WebHostCLIRunner.run(app, configuration: configuration)
        case .choices:
            try await WebHostCLIRunner.run(ChoiceApplication(theme: theme), configuration: configuration)
        case .textEntry:
            try await WebHostCLIRunner.run(TextEntryApplication(theme: theme), configuration: configuration)
        case .feedback:
            try await WebHostCLIRunner.run(FeedbackApplication(theme: theme), configuration: configuration)
        case .files:
            let startingDirectory = URL(
                fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
            try await WebHostCLIRunner.run(
                FileSelectionApplication(directory: startingDirectory, theme: theme),
                configuration: configuration
            )
        case .keyboardHelp:
            try await WebHostCLIRunner.run(HelpApplication(theme: theme), configuration: configuration)
        case .tabs:
            try await WebHostCLIRunner.run(TabsApplication(theme: theme), configuration: configuration)
        case .pagination:
            try await WebHostCLIRunner.run(PaginationApplication(theme: theme), configuration: configuration)
        case .viewport:
            try await WebHostCLIRunner.run(ViewportApplication(theme: theme), configuration: configuration)
        case .tree:
            try await WebHostCLIRunner.run(TreeApplication(theme: theme), configuration: configuration)
        case .forms:
            try await WebHostCLIRunner.run(FormsApplication(theme: theme), configuration: configuration)
        case .timers:
            try await WebHostCLIRunner.run(TimersApplication(theme: theme), configuration: configuration)
        case .metrics:
            try await WebHostCLIRunner.run(MetricsApplication(theme: theme), configuration: configuration)
        case .inbox:
            try await WebHostCLIRunner.run(InboxApplication(theme: theme), configuration: configuration)
        case .diff:
            try await WebHostCLIRunner.run(DiffApplication(theme: theme), configuration: configuration)
        }
    }

    @MainActor
    private func renderSnapshot(_ example: DashboardExample, theme: ExampleTheme) throws -> String {
        switch example {
        case .dashboard:
            render(DashboardView(scenario: scenario, theme: theme, shouldAnimate: false, isPaused: paused))
        case .choices:
            render(ChoiceExampleView(theme: theme))
        case .textEntry:
            render(TextEntryExampleView(theme: theme))
        case .feedback:
            render(FeedbackExampleView(theme: theme))
        case .files:
            throw Self.fileSnapshotError
        case .keyboardHelp:
            render(HelpExampleView(theme: theme))
        case .tabs:
            render(TabsExampleView(theme: theme))
        case .pagination:
            render(PaginationExampleView(theme: theme))
        case .viewport:
            render(ViewportExampleView(theme: theme))
        case .tree:
            render(TreeExampleView(theme: theme))
        case .forms:
            render(GroupedFormExampleView(theme: theme))
        case .timers:
            render(TimerExampleView(theme: theme))
        case .metrics:
            render(MetricsExampleView(theme: theme))
        case .inbox:
            render(InboxExampleView(theme: theme))
        case .diff:
            render(DiffExampleView(theme: theme))
        }
    }

    @MainActor
    private func render(_ view: some View) -> String {
        let frame = DefaultRenderer().render(
            view.environment(\.terminalSize, CellSize(width: width, height: height)),
            proposal: ProposedSize(width: width, height: height),
            frameInstant: .zero
        )
        return frame.rasterSurface.lines.joined(separator: "\n")
    }
}
