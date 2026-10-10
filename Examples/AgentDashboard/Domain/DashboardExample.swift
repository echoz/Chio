/// One resolved example; command-line flags are only an input representation.
enum DashboardExample {
    case dashboard
    case choices
    case textEntry
    case feedback
    case files
    case keyboardHelp
    case tabs
    case pagination
    case viewport
    case tree
    case forms
    case timers
    case metrics
    case inbox
    case diff

    var isFocusedExample: Bool {
        switch self {
        case .dashboard:
            false
        case .choices, .textEntry, .feedback, .files, .keyboardHelp, .tabs,
             .pagination, .viewport, .tree, .forms, .timers, .metrics, .inbox, .diff:
            true
        }
    }

    var defaultTheme: ExampleTheme {
        switch self {
        case .metrics:
            .btop
        case .dashboard, .choices, .textEntry, .feedback, .files, .keyboardHelp,
             .tabs, .pagination, .viewport, .tree, .forms, .timers, .inbox, .diff:
            .default
        }
    }
}

extension DashboardExample: Hashable {}
extension DashboardExample: Codable {}
extension DashboardExample: Sendable {}
