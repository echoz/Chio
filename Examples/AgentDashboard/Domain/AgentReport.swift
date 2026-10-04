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
            outcome = "The run was **\(Int(progress * 100))% complete** when this report opened. Reopen it to read the latest state."
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

        > Local simulation. This report is a snapshot; no external commands or services were used.

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
            if character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
               (0x21...0x2F).contains(scalar.value) || (0x3A...0x40).contains(scalar.value)
                || (0x5B...0x60).contains(scalar.value) || (0x7B...0x7E).contains(scalar.value) {
                result.append("\\")
            }
            result.append(character)
        }
    }
}

extension AgentReport: Identifiable {
    var id: Agent.ID { agent.id }
}

extension AgentReport: Equatable {}
extension AgentReport: Sendable {}
