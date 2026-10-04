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
    @State private var isLight: Bool
    @State private var isPaused: Bool
    @State private var openedAgent: String?
    @State private var isCreating = false
    @State private var creationNumber = 0
    @State private var draft = AgentDraft()
    @State private var creationEntry = CreateAgentView.Entry.name
    @State private var validateOnArrival = false
    @State private var isReturningFromCreation = false
    @State private var report: AgentReport?
    let animates: Bool

    init(scenario: DashboardScenario = .normal, light: Bool = false, animates: Bool = true, paused: Bool = false) {
        _agents = State(wrappedValue: scenario.agents)
        _selection = State(wrappedValue: scenario == .noMatches ? nil : scenario.agents.first?.id)
        _query = State(wrappedValue: scenario.query)
        _isLight = State(wrappedValue: light)
        _isPaused = State(wrappedValue: paused)
        self.animates = animates
    }

    private var theme: ChioTheme { isLight ? .light : .default }
    private var selectedAgent: Agent? { agents.first { $0.id == selection } }

    private func runSelected() {
        guard let index = agents.firstIndex(where: { $0.id == selection }) else { return }
        agents[index].phase = .running(progress: 0)
        isPaused = false
    }

    private func failSelected() {
        guard let index = agents.firstIndex(where: { $0.id == selection }) else { return }
        agents[index].phase = .failed
    }

    private func toggleEmpty() {
        agents = agents.isEmpty ? Agent.examples : []
        selection = agents.first?.id
        query = ""
    }

    private func handleKey(_ press: KeyPress) -> KeyPressResult {
        // A report can be requested before the input batch reaches its cover.
        // Keep subsequent keys out of the dashboard during that handoff.
        if report != nil {
            if press.key == .escape { report = nil }
            if press == KeyPress(.character("t"), modifiers: .ctrl) { isLight.toggle() }
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
                isLight.toggle()
                return .handled
            }
            guard press.modifiers.subtracting(.shift).isEmpty else { return .handled }
            switch press.key {
            case .character(let character) where creationEntry == .name: draft.name.append(character)
            case .space where creationEntry == .name: draft.name.append(" ")
            case .backspace:
                if creationEntry == .name && !draft.name.isEmpty { draft.name.removeLast() }
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
            draft = AgentDraft()
            creationEntry = .name
            validateOnArrival = false
            creationNumber += 1
            isCreating = true
        case .character("q"):
            _ = requestTermination()
        case .character("t"):
            isLight.toggle()
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
                } else {
                    KeyHint("↑↓", "navigate")
                    KeyHint("↵", "report")
                    KeyHint("/", "filter")
                    KeyHint("n", "new")
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
                                    openedAgent = agent.name
                                    report = AgentReport(agent: agent)
                                }
                                .onSearchFocusChange { isSearching = $0 }
                                .onResultKeyPress(perform: handleKey)
                                .onKeyPress { press in
                                    // Until the appended row renders, native list handlers
                                    // still hold the old items and can overwrite selection.
                                    if isReturningFromCreation { return .handled }
                                    return isCreating || report != nil ? handleKey(press) : .ignored
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
        .fullScreenCover(isPresented: $isCreating) {
            CreateAgentView(draft: $draft, isLight: $isLight, entry: creationEntry,
                            validateOnArrival: validateOnArrival,
                            create: createAgent, cancel: { isCreating = false })
                .id(creationNumber)
        }
        .fullScreenCover(item: $report) { report in
            AgentReportView(report: report, isLight: $isLight, close: { self.report = nil })
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
