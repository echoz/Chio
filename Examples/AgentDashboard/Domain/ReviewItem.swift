import Foundation

/// A local review snapshot used by the inbox example.
struct ReviewItem {
    let id: Int
    let title: String
    let repository: String
    let author: String
    let status: Status
    let updatedAt: Date
    let summary: String
    let files: [String]

    enum Status: String {
        case review
        case draft
        case changesRequested

        var title: String {
            switch self {
            case .review: "Ready for review"
            case .draft: "Draft"
            case .changesRequested: "Changes requested"
            }
        }
    }

    enum Order: String {
        case recent
        case repository

        var title: String {
            switch self {
            case .recent: "Recent"
            case .repository: "Repository"
            }
        }

        var next: Self {
            switch self {
            case .recent: .repository
            case .repository: .recent
            }
        }
    }

    var searchText: String { "\(title) \(repository) \(author) #\(id)" }

    static func ordered(_ items: [Self], by order: Order) -> [Self] {
        items.sorted { lhs, rhs in
            if order == .repository, lhs.repository != rhs.repository {
                return lhs.repository < rhs.repository
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    static let examples: [Self] = [
        fixture(214, "Keep selection when search changes", "Chio", "maya", .review, 1_791_216_000,
            ["Sources/Chio/Presentation/SearchableList.swift", "Tests/ChioTests/Presentation/SearchableListTests.swift"],
            """
            ## Selection follows the visible results

            Retain the selected identity while it still matches the query. Reveal the first result when that identity is filtered out.

            - Cover fast edits arriving in one input batch.
            - Keep the empty-results message distinct from an empty collection.

            ## Review focus

            Check the transition from the search field into the result list.

            ```swift
            let visible = items.filter { $0.title.contains(query) }
            let selected = visible.first { $0.id == selection } ?? visible.first
            ```
            """),
        fixture(215, "Restore reader focus after dismissal", "SwiftTUI", "owen", .review, 1_791_215_400,
            ["Sources/SwiftTUIViews/Navigation/FullScreenCover.swift"],
            "Return to the previously focused control when the full-screen reader closes.\n\n- Exercise repeated open and close cycles.\n- Retain the search field's text."),
        fixture(216, "Group release notes by component", "Tools", "lina", .draft, 1_791_214_800,
            ["Sources/ReleaseNotes/ReleaseNotes.swift"],
            "Collect local changes into component sections. The heading vocabulary is still being refined."),
        fixture(217, "Clamp compact panel width", "Chio", "dev", .changesRequested, 1_791_214_200,
            ["Sources/Chio/Presentation/Styles/ChioGroupBoxStyle.swift"],
            "## Requested follow-up\n\nThe border title can overhang a two-column panel.\n\n- Bound its width before adding padding.\n- Include a neighboring-content regression."),
        fixture(218, "Keep scroll position across theme changes", "SwiftTUI", "maya", .review, 1_791_213_600,
            ["Sources/SwiftTUIViews/ScrollView.swift"],
            "Theme replacement should preserve the native scroll position and focused child. Check both ends of a long document."),
        fixture(219, "Explain local snapshot fixtures", "Tools", "owen", .review, 1_791_213_000,
            ["Docs/Snapshots.md"],
            "Document how fixed inputs produce repeatable captures. Add an example of inspecting a narrow terminal image."),
        fixture(220, "Preview review summaries in Markdown", "Chio", "lina", .draft, 1_791_212_400,
            ["Examples/AgentDashboard/Presentation/InboxExampleView.swift"],
            "## Preview composition\n\nUse the existing Markdown renderer for a selected review's summary.\n\n- Place the preview beside wide lists.\n- Open a full-screen reader in compact layouts.\n- Keep query and selection above the layout alternatives."),
        fixture(221, "Measure empty native text editors", "SwiftTUI", "dev", .changesRequested, 1_791_211_800,
            ["Sources/SwiftTUIViews/TextEditor.swift", "Tests/SwiftTUIViewsTests/TextEditorTests.swift"],
            "The empty editor needs a bounded viewport. Review the measurement rule with a placeholder and with multiline content."),
        fixture(222, "Add a serial verification preset", "Tools", "maya", .review, 1_791_211_200,
            ["Scripts/verify-local.sh"],
            "Offer one local verification entry point with serial test execution. Preserve failures and show the failed check's output."),
        fixture(223, "Clarify keyboard help contexts", "Chio", "owen", .review, 1_791_210_600,
            ["Examples/AgentDashboard/Presentation/HelpExampleView.swift"],
            "Describe available shortcuts for the list, search field and reader. Keep the descriptions separate from action registration."),
        fixture(224, "Explore pointer hit regions for tabs", "SwiftTUI", "lina", .draft, 1_791_210_000,
            ["Sources/SwiftTUIViews/TabView.swift"],
            "## Open question\n\nShould the whole tab label activate on a click?\n\n- Compare label and padding hit regions.\n- Check keyboard focus after pointer selection."),
        fixture(225, "Remove timestamps from golden captures", "Tools", "dev", .changesRequested, 1_791_209_400,
            ["Sources/SnapshotRunner/Capture.swift"],
            "Pass the capture timestamp explicitly. The current clock read makes otherwise identical fixture images differ."),
        fixture(226, "Improve code block contrast", "Chio", "maya", .review, 1_791_208_800,
            ["Sources/Chio/Domain/ChioTheme.swift"],
            "Tune Swift keyword and comment colors in the light theme. Preserve the source text and horizontal scrolling behavior."),
        fixture(227, "Retain focus in disabled list rows", "SwiftTUI", "owen", .review, 1_791_208_200,
            ["Sources/SwiftTUIViews/List.swift"],
            "Keep disabled choices readable while preventing activation. Verify selection and focus remain distinct observations."),
        fixture(228, "Draft fixture index for demos", "Tools", "lina", .draft, 1_791_207_600,
            ["Docs/Examples.md"],
            "List the local demonstration scenarios and their fixed inputs. Review names before linking them from the example guide."),
        fixture(229, "Preserve raw multiline form notes", "Chio", "dev", .review, 1_791_207_000,
            ["Examples/AgentDashboard/Domain/RunSettingsDraft.swift"],
            "Keep hidden notes in the editable snapshot. Saving accepts the current notes; cancellation restores the accepted snapshot."),
    ]

    private static func fixture(
        _ id: Int, _ title: String, _ repository: String, _ author: String,
        _ status: Status, _ epoch: TimeInterval, _ files: [String], _ summary: String
    ) -> Self {
        Self(id: id, title: title, repository: repository, author: author, status: status,
             updatedAt: Date(timeIntervalSince1970: epoch), summary: summary, files: files)
    }
}

extension ReviewItem: Identifiable {}
extension ReviewItem: Codable {}
extension ReviewItem: Hashable {}
extension ReviewItem: Sendable {}

extension ReviewItem.Status: Codable {}
extension ReviewItem.Status: Hashable {}
extension ReviewItem.Status: Sendable {}

extension ReviewItem.Order: Codable {}
extension ReviewItem.Order: Hashable {}
extension ReviewItem.Order: Sendable {}
