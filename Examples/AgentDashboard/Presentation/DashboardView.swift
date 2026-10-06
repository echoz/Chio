import Chio
import Foundation
import SwiftTUI

@MainActor
struct DashboardView {
    @Environment(\.requestTermination) private var requestTermination
    @State private var agents: [Agent]
    @State private var selection: Agent.ID?
    @State private var query: String
    @State private var isSearching = false
    @State private var themeChoice: ExampleTheme
    @State private var isPaused: Bool
    @State private var openedAgent: String?
    @State private var isCreating = false
    @State private var creationNumber = 0
    @State private var draft = AgentDraft()
    @State private var creationEntry = CreateAgentView.Entry.name
    @State private var validateOnArrival = false
    @State private var isReturningFromCreation = false
    @State private var report: AgentReport?
    @State private var showsCommands = false
    @State private var commandQuery = ""
    @State private var pendingCommand: Command?
    let animates: Bool

    private enum Command {
        case create, run, report, theme, pause
    }

    init(scenario: DashboardScenario = .normal, theme: ExampleTheme = .default, animates: Bool = true, paused: Bool = false) {
        _agents = State(wrappedValue: scenario.agents)
        _selection = State(wrappedValue: scenario == .noMatches ? nil : scenario.agents.first?.id)
        _query = State(wrappedValue: scenario.query)
        _themeChoice = State(wrappedValue: theme)
        _isPaused = State(wrappedValue: paused)
        self.animates = animates
    }

    private var theme: ChioTheme { themeChoice.theme }
    private var selectedAgent: Agent? { agents.first { $0.id == selection } }

    private func beginCreation() {
        draft = AgentDraft()
        creationEntry = .name
        validateOnArrival = false
        creationNumber += 1
        isCreating = true
    }

    private func openReport(_ agent: Agent) {
        openedAgent = agent.name
        report = AgentReport(agent: agent)
    }

    private func performPendingCommand() {
        // Let native palette focus return before presenting a destination cover.
        let command = pendingCommand
        pendingCommand = nil
        switch command {
        case .create: beginCreation()
        case .run: runSelected()
        case .report:
            if let selectedAgent { openReport(selectedAgent) }
        case .theme: themeChoice = themeChoice.next
        case .pause: isPaused.toggle()
        case nil: break
        }
    }

    private func runSelected() {
        guard let index = agents.firstIndex(where: { $0.id == selection }) else { return }
        agents[index] = agents[index].replacingPhase(.running(progress: .zero))
        isPaused = false
    }

    private func failSelected() {
        guard let index = agents.firstIndex(where: { $0.id == selection }) else { return }
        agents[index] = agents[index].replacingPhase(.failed)
    }

    private func toggleEmpty() {
        agents = agents.isEmpty ? Agent.examples : []
        selection = agents.first?.id
        query = ""
    }

    private func handleKey(_ press: KeyPress) -> KeyPressResult {
        // Carry simple type-ahead until the native palette editor exists,
        // without firing dashboard shortcuts during the opening input batch.
        if showsCommands {
            guard press.modifiers.subtracting(.shift).isEmpty else { return .handled }
            switch press.key {
            case .character(let character): commandQuery.append(character)
            case .space: commandQuery.append(" ")
            case .backspace:
                if !commandQuery.isEmpty { commandQuery.removeLast() }
            case .escape: showsCommands = false
            default: break
            }
            return .handled
        }
        // A report can be requested before the input batch reaches its cover.
        // Keep subsequent keys out of the dashboard during that handoff.
        if report != nil {
            if press.key == .escape { report = nil }
            if press == KeyPress(.character("t"), modifiers: .ctrl) { themeChoice = themeChoice.next }
            return .handled
        }
        // A read can contain n and subsequent keys before the cover appears.
        // Prevent stale dashboard handlers from executing shortcuts during that
        // handoff; native controls own input once the cover has focus.
        if isCreating {
            if press == KeyPress(.character("s"), modifiers: .ctrl) {
                submitDuringPresentation()
                return .handled
            }
            if press == KeyPress(.character("t"), modifiers: .ctrl) {
                themeChoice = themeChoice.next
                return .handled
            }
            guard press.modifiers.subtracting(.shift).isEmpty else { return .handled }
            switch press.key {
            case .character(let character) where creationEntry == .name:
                draft = draft.replacing(name: draft.name + String(character))
            case .space where creationEntry == .name:
                draft = draft.replacing(name: draft.name + " ")
            case .backspace:
                if creationEntry == .name && !draft.name.isEmpty {
                    draft = draft.replacing(name: String(draft.name.dropLast()))
                }
            case .tab:
                creationEntry = press.modifiers.contains(.shift) ? .name : .role
            case .return: submitDuringPresentation()
            case .escape: isCreating = false
            default: break
            }
            return .handled
        }
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .character("n"):
            beginCreation()
        case .character("q"):
            _ = requestTermination()
        case .character("t"):
            themeChoice = themeChoice.next
        case .character("r"):
            runSelected()
        case .character("f"):
            failSelected()
        case .character("p"):
            isPaused.toggle()
        case .character("e"):
            toggleEmpty()
        default:
            return .ignored
        }
        return .handled
    }

    private func createAgent() {
        guard isCreating, let agent = draft.makeAgent(id: UUID().uuidString) else { return }
        agents.append(agent)
        query = ""
        selection = agent.id
        openedAgent = agent.name
        if draft.startImmediately { isPaused = false }
        isCreating = false
        isReturningFromCreation = true
    }

    private func submitDuringPresentation() {
        if draft.issues.isEmpty {
            createAgent()
        } else {
            validateOnArrival = true
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text("chio").bold().foregroundStyle(theme.colors.accent)
                    Text("/ agent workspace").foregroundStyle(theme.colors.secondaryText)
                }
                Text("Beautiful terminal interfaces for Swift.")
                    .foregroundStyle(theme.colors.mutedText)
                    .lineLimit(1)
            }
            Spacer()
            if !compact {
                Text(isPaused ? "○ paused" : "● local demo")
                    .foregroundStyle(isPaused ? theme.colors.warning : theme.colors.success)
            }
        }
    }

    private func footer(brief: Bool) -> some View {
        StatusBar {
            KeyHints {
                if isSearching {
                    KeyHint("type", "filter")
                    KeyHint("↵", "results")
                    KeyHint("esc", "clear")
                    KeyHint("tab", "next")
                    KeyHint("^K", "commands")
                } else {
                    KeyHint("↑↓", "navigate")
                    KeyHint("↵", "report")
                    KeyHint("/", "filter")
                    KeyHint("n", "new")
                    KeyHint("^K", "commands")
                    if !brief {
                        KeyHint("r", "run")
                        KeyHint("f", "fail")
                        KeyHint("p", isPaused ? "resume" : "pause")
                        KeyHint("e", "empty")
                        KeyHint("t", "theme")
                    }
                    KeyHint("q", "quit")
                }
            }
        }
    }
}

extension DashboardView: View {
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 88
            let compact = !wide || geometry.size.height < 30
            let brief = geometry.size.height < 26
            let layoutTheme = ChioTheme(
                colors: theme.colors,
                spacing: .init(sectionGap: compact ? 0 : 1),
                treatments: theme.treatments
            )
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 2))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 1))

            VStack(alignment: .leading, spacing: 1) {
                header(compact: geometry.size.width < 60)
                GeometryReader { contentGeometry in
                    layout {
                        GroupBox("Agents") {
                            ScrollViewReader { proxy in
                                SearchableList(agents, selection: $selection, query: $query, searchText: \.name) { agent in
                                    AgentRow(agent: agent, compact: compact)
                                }
                                .filtering(.fuzzy)
                                .onActivate { agent in
                                    openReport(agent)
                                }
                                .onSearchFocusChange { isSearching = $0 }
                                .onResultKeyPress(perform: handleKey)
                                .onKeyPress { press in
                                    // Until the appended row renders, native list handlers
                                    // still hold the old items and can overwrite selection.
                                    if isReturningFromCreation { return .handled }
                                    return isCreating || report != nil || showsCommands ? handleKey(press) : .ignored
                                }
                                .onChange(of: agents.count) {
                                    if agents.last?.id == selection {
                                        proxy.scrollTo(edge: .bottom)
                                    }
                                    isReturningFromCreation = false
                                }
                            }
                        }
                        .frame(width: wide ? max(35, (geometry.size.width - 6) / 2) : nil,
                               height: wide || brief ? contentGeometry.size.height : max(8, contentGeometry.size.height - 7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        if wide || !brief {
                            AgentDetail(agent: selectedAgent, compact: compact, run: runSelected, fail: failSelected)
                                .onKeyPress(perform: handleKey)
                        }
                    }
                    .frame(width: contentGeometry.size.width, height: contentGeometry.size.height, alignment: .topLeading)
                }

                if let openedAgent, !brief {
                    Text("Opened \(openedAgent) · activity shown above")
                        .foregroundStyle(theme.colors.secondaryText)
                        .layoutPriority(1)
                }
                footer(brief: brief)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .chioTheme(layoutTheme)
        }
        .panel(id: "dashboard")
        .keyCommand("Commands", key: .character("k"), modifiers: .ctrl,
                    isEnabled: !isCreating && report == nil && !showsCommands) {
            guard !isCreating, report == nil, !showsCommands else { return }
            commandQuery = ""
            showsCommands = true
        }
        .paletteCommand(name: "Create agent", description: "Set up a new simulated agent") {
            pendingCommand = .create
        }
        .paletteCommand(name: selectedAgent?.phase == .failed ? "Retry selected agent" : "Run selected agent",
                        description: selectedAgent?.name ?? "Select an agent first",
                        isEnabled: selectedAgent != nil) {
            pendingCommand = .run
        }
        .paletteCommand(name: "Open agent report",
                        description: selectedAgent?.name ?? "Select an agent first",
                        isEnabled: selectedAgent != nil) {
            pendingCommand = .report
        }
        .paletteCommand(name: "Switch to \(themeChoice.next.rawValue) theme",
                        description: "Change the workspace appearance") {
            pendingCommand = .theme
        }
        .paletteCommand(name: isPaused ? "Resume simulation" : "Pause simulation",
                        description: "Control the local demo") {
            pendingCommand = .pause
        }
        .paletteSheet("Commands", isPresented: $showsCommands)
        .onChange(of: showsCommands) { _, isPresented in
            if !isPresented { performPendingCommand() }
        }
        .paletteStyle(ChioPaletteStyle(theme: theme, initialQuery: commandQuery))
        .fullScreenCover(isPresented: $isCreating) {
            CreateAgentView(draft: $draft, themeChoice: $themeChoice, entry: creationEntry,
                            validateOnArrival: validateOnArrival,
                            create: createAgent, cancel: { isCreating = false })
                .id(creationNumber)
        }
        .fullScreenCover(item: $report) { report in
            AgentReportView(report: report, themeChoice: $themeChoice, close: { self.report = nil })
        }
        .task {
            guard animates else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(600)) }
                catch { return }
                if !isPaused { agents = AgentSimulation.advance(agents) }
            }
        }
    }
}
