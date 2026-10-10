import Chio

/// A parsed snapshot of one simulated run, captured when its report is opened.
struct AgentReport {
    let agent: Agent
    let document: MarkdownDocument

    init(agent: Agent) {
        self.agent = agent
        document = MarkdownDocument(Self.source(for: agent))
    }

    private static func source(for agent: Agent) -> String {
        let outcome: String
        let checks: String
        switch agent.phase {
        case .idle:
            outcome = "This agent is ready. Return to the dashboard and press **r** to start a simulated run."
            checks = "- [ ] Prepare workspace\n- [ ] Compile package\n- [ ] Run checks"
        case .running(let progress):
            outcome = "The run was **\(Int(progress.fraction * 100))% complete** when this report opened. Reopen it to read the latest state."
            checks = "- [x] Prepare workspace\n- [ ] Finish compilation and checks"
        case .completed:
            outcome = "**All checks passed.** The simulated run is complete. Your terminal looks *chio*."
            checks = "- [x] Prepare workspace\n- [x] Compile package\n- [x] Run checks"
        case .failed:
            outcome = "**A simulated check failed.** Return to the dashboard and press **r** to try a successful run."
            checks = "- [x] Prepare workspace\n- [x] Compile package\n- [ ] Resolve the simulated failure"
        }
        let activity = agent.activity.map { "- \(escape($0))" }.joined(separator: "\n")
        return """
        # \(escape(agent.name))

        **\(agent.phase.label)** · \(escape(agent.summary))

        Read the [project docs](Docs/Design.md) or review the [outcome](#outcome).

        > Local simulation. This report is a snapshot; no external commands or services were used.

        ## Table example

        Illustrative timings, not measurements from this run.

        | Stage | Result | Time |
        | :--- | :---: | ---: |
        | Prepare | **Ready** | 0.4 s |
        | Compile | **Passed** | 12.8 s |
        | `swift test` | **Passed** | 3.2 s |

        Tab moves through links to the table; left/right scroll it on narrow screens. Shift-Tab returns through links to the report.

        ## Activity

        \(activity)

        ## Checks

        \(checks)

        ## Example workflow

        A Swift project might use these commands. They are shown as an example and were **not executed** by this demo.

        ```sh
        swift build
        swift test
        ```

        Swift fences use the current theme's syntax colors. This view composes native controls; the example stays literal and can scroll horizontally.

        ```swift
        // A small view, styled by its surrounding theme.
        struct RunSummary: View {
            let completed: Double = 0.78

            var body: some View {
                GroupBox("Build Agent") {
                    ProgressView(value: completed, total: 1.0)
                    Text("Preparing a beautiful terminal interface, one small component at a time.")
                }
            }
        }
        ```

        ## Reading the results

        1. Review the activity and check statuses above.
        2. Return to the dashboard to run or retry the agent.
        3. Open its report again for a fresh snapshot.

        ### A small design system, composed

        Headings, **strong text**, *emphasis*, `inline code`, lists, and quoted notes all share the current Chio theme.

        - Use the arrow keys to read more.
        - Home and End move to the start and end.
        - Tab can focus a code block; left and right scroll long code lines.

        ## Outcome

        \(outcome)

        *End of report.*
        """
    }

    // User-authored names and descriptions are literal Markdown content.
    private static func escape(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first {
                let isEarlyASCIIPunctuation = (0x21...0x2F).contains(scalar.value)
                let isMiddleASCIIPunctuation = (0x3A...0x40).contains(scalar.value)
                let isBracketASCIIPunctuation = (0x5B...0x60).contains(scalar.value)
                let isFinalASCIIPunctuation = (0x7B...0x7E).contains(scalar.value)
                if isEarlyASCIIPunctuation || isMiddleASCIIPunctuation
                    || isBracketASCIIPunctuation || isFinalASCIIPunctuation {
                    result.append("\\")
                }
            }
            result.append(character)
        }
    }
}

extension AgentReport: Identifiable {
    var id: Agent.ID { agent.id }
}

extension AgentReport: Equatable {}
extension AgentReport: Hashable {}
extension AgentReport: Sendable {}
