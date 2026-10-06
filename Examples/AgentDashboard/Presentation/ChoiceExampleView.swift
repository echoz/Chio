import Chio
import SwiftTUI

/// A bounded, local two-step form demonstrating single and multiple choices.
@MainActor
struct ChoiceExampleView {
    @Environment(\.requestTermination) private var requestTermination
    @Environment(\.terminalSize) private var terminalSize
    @State private var draft: ChoiceDraft
    @State private var step: Step
    @State private var themeChoice: ExampleTheme
    @State private var languageQuery = ""
    @State private var capabilityQuery = ""
    @State private var showsValidation: Bool
    @State private var feedback = Feedback.editing
    let original: ChoiceDraft
    private let availableCapabilities = Set(ChoiceDraft.Capability.allCases.filter { $0 != .deploy })

    enum Step { case language, capabilities }

    enum Feedback {
        case editing
        case saved(ChoiceDraft)
        case rejected
        case cancelled
        case reset

        var message: String {
            switch self {
            case .editing: "Local demo · unsaved choices"
            case .saved(let draft): "Saved: \(draft.summary)"
            case .rejected: "Not saved · check the errors"
            case .cancelled: "Cancelled · original choices restored"
            case .reset: "Reset · choose again"
            }
        }
    }

    // Initial step and validation visibility also allow focused snapshot coverage.
    init(theme: ExampleTheme = .default, initialDraft: ChoiceDraft = ChoiceDraft(),
         initialStep: Step = .language, showsValidation: Bool = false) {
        original = initialDraft
        _draft = State(wrappedValue: initialDraft)
        _step = State(wrappedValue: initialStep)
        _themeChoice = State(wrappedValue: theme)
        _showsValidation = State(wrappedValue: showsValidation)
    }

    private var theme: ChioTheme { themeChoice.theme }

    private var languageSelection: Binding<ChoiceDraft.Language?> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.language }, set: {
            if let language = $0 {
                storage.wrappedValue = storage.wrappedValue.replacing(language: language)
            }
        })
    }

    private var capabilities: Binding<Set<ChoiceDraft.Capability>> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.capabilities }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(capabilities: $0)
        })
    }

    private func advance() {
        if step == .language {
            continueToCapabilities()
            return
        }
        save()
    }

    private func continueToCapabilities() {
        guard step == .language else { return }
        step = .capabilities
    }

    private func save() {
        guard step == .capabilities else { return }
        showsValidation = true
        guard draft.validationMessage(availableCapabilities: availableCapabilities) == nil else {
            feedback = .rejected
            return
        }
        feedback = .saved(draft)
    }

    private func cancel() {
        draft = original
        step = .language
        languageQuery = ""
        capabilityQuery = ""
        showsValidation = false
        feedback = .cancelled
    }

    private func reset() {
        draft = ChoiceDraft()
        languageQuery = ""
        capabilityQuery = ""
        showsValidation = false
        feedback = .reset
    }

    private func hints(compact: Bool) -> some View {
        KeyHints {
            KeyHint("tab", "next")
            KeyHint("/", "search")
            KeyHint("esc", "clear")
            KeyHint(step == .language ? "enter" : "space/↵", step == .language ? "choose" : "toggle")
            KeyHint("^S", step == .language ? "next" : "save")
            if step == .capabilities { KeyHint("^B", "back") }
            KeyHint("^X", "cancel")
            if !compact { KeyHint("^R", "reset") }
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }
}

extension ChoiceExampleView.Step: Equatable {}

extension ChoiceExampleView: View {
    var body: some View {
        let compact = terminalSize.width < 50
        let short = terminalSize.height < 24
        let controlHeight = max(7, min(14, terminalSize.height - (short ? 11 : 13)))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ choices").foregroundStyle(theme.colors.secondaryText)
            }
            if !short {
                Text(step == .language ? "1 / 2 · Language" : "2 / 2 · Capabilities")
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Group {
                if step == .language {
                    FormField(short ? "Language · 1 / 2" : "Language", description: "Enter a result to continue") {
                        SearchableList(ChoiceDraft.Language.allCases, selection: languageSelection,
                                       query: $languageQuery, prompt: "Find a language…", searchText: { $0.label }) {
                            Text($0.label)
                        }
                        .onActivate { _ in continueToCapabilities() }
                        .frame(height: controlHeight)
                    }
                } else {
                    FormField("Capabilities · \(draft.capabilities.count) / 3" + (short ? " · 2 / 2" : ""),
                              description: "Choose 1–3 · Deploy unavailable",
                              error: showsValidation ? draft.validationMessage(availableCapabilities: availableCapabilities) : nil) {
                        SearchableChecklist(ChoiceDraft.Capability.allCases, selection: capabilities,
                                            query: $capabilityQuery, prompt: "Find a capability…",
                                            searchText: { "\($0.label) \($0.description)" },
                                            isEnabled: { availableCapabilities.contains($0) }) { capability in
                            HStack(spacing: 1) {
                                Text(capability.label)
                                if !compact && capability != .deploy {
                                    Text(capability.description).foregroundStyle(theme.colors.secondaryText)
                                }
                            }
                        }
                        .frame(height: controlHeight)
                    }
                }
            }
            .id(step)

            Text(feedback.message)
                .foregroundStyle(feedback == .rejected ? theme.colors.error : theme.colors.secondaryText)
                .lineLimit(1)
            HStack(spacing: 1) {
                if step == .capabilities { Button("Back") { step = .language } }
                Button(step == .language ? "Next" : "Save",
                       action: step == .language ? continueToCapabilities : save)
                Button("Cancel", action: cancel)
            }
            Spacer(minLength: 0)
            if short {
                hints(compact: true)
            } else {
                StatusBar { hints(compact: compact) }
            }
        }
        .padding(.horizontal, short ? 0 : 1)
        .padding(.vertical, short ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .chioTheme(short ? theme.replacing(spacing: theme.spacing.replacing(sectionGap: 0)) : theme)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("s"): advance()
            case .character("b"): step = .language
            case .character("x"): cancel()
            case .character("r"): reset()
            case .character("t"): themeChoice = themeChoice.next
            case .character("q"): _ = requestTermination()
            default: return .ignored
            }
            return .handled
        }
        .onChange(of: draft) {
            if case .saved(let saved) = feedback, saved != draft { feedback = .editing }
        }
    }
}

extension ChoiceExampleView.Step: Hashable {}
extension ChoiceExampleView.Step: Sendable {}
extension ChoiceExampleView.Feedback: Equatable {}
extension ChoiceExampleView.Feedback: Hashable {}
extension ChoiceExampleView.Feedback: Codable {}
extension ChoiceExampleView.Feedback: Sendable {}
