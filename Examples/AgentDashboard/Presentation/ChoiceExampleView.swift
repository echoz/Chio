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
    private let availableCapabilities = Set(ChoiceDraft.Capability.allCases.filter { $0.isAvailableInDemo })

    enum Step {
        case language, capabilities

        var isLanguage: Bool {
            switch self {
            case .language: true
            case .capabilities: false
            }
        }
        var isCapabilities: Bool {
            switch self {
            case .language: false
            case .capabilities: true
            }
        }
        var title: String {
            switch self {
            case .language: "1 / 2 · Language"
            case .capabilities: "2 / 2 · Capabilities"
            }
        }
        var activationKey: String {
            switch self {
            case .language: "enter"
            case .capabilities: "space/↵"
            }
        }
        var activationHint: String {
            switch self {
            case .language: "choose"
            case .capabilities: "toggle"
            }
        }
        var advanceHint: String {
            switch self {
            case .language: "next"
            case .capabilities: "save"
            }
        }
        var actionTitle: String {
            switch self {
            case .language: "Next"
            case .capabilities: "Save"
            }
        }
    }

    enum Feedback {
        case editing
        case saved(ChoiceDraft)
        case rejected
        case cancelled
        case reset

        var isRejected: Bool {
            switch self {
            case .rejected: true
            case .editing, .saved, .cancelled, .reset: false
            }
        }

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
        switch step {
        case .language: continueToCapabilities()
        case .capabilities: save()
        }
    }

    private func continueToCapabilities() {
        switch step {
        case .language: step = .capabilities
        case .capabilities: break
        }
    }

    private func save() {
        switch step {
        case .language: return
        case .capabilities: break
        }
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

    private func hints(isCompact: Bool) -> some View {
        KeyHints {
            KeyHint("tab", "next")
            KeyHint("/", "search")
            KeyHint("esc", "clear")
            KeyHint(step.activationKey, step.activationHint)
            KeyHint("^S", step.advanceHint)
            if step.isCapabilities { KeyHint("^B", "back") }
            KeyHint("^X", "cancel")
            if !isCompact { KeyHint("^R", "reset") }
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }
}

extension ChoiceExampleView.Step: Equatable {}

extension ChoiceExampleView: View {
    var body: some View {
        let isCompact = terminalSize.width < 50
        let isShort = terminalSize.height < 24
        let controlHeight = max(7, min(14, terminalSize.height - (isShort ? 11 : 13)))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ choices").foregroundStyle(theme.colors.secondaryText)
            }
            if !isShort {
                Text(step.title)
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Group {
                if step.isLanguage {
                    FormField(isShort ? "Language · 1 / 2" : "Language", description: "Enter a result to continue") {
                        SearchableList(ChoiceDraft.Language.allCases, selection: languageSelection,
                                       query: $languageQuery, prompt: "Find a language…", searchText: { $0.label }) {
                            Text($0.label)
                        }
                        .onActivate { _ in continueToCapabilities() }
                        .frame(height: controlHeight)
                    }
                } else {
                    FormField("Capabilities · \(draft.capabilities.count) / 3" + (isShort ? " · 2 / 2" : ""),
                              description: "Choose 1–3 · Deploy unavailable",
                              error: showsValidation ? draft.validationMessage(availableCapabilities: availableCapabilities) : nil) {
                        SearchableChecklist(ChoiceDraft.Capability.allCases, selection: capabilities,
                                            query: $capabilityQuery, prompt: "Find a capability…",
                                            searchText: { "\($0.label) \($0.description)" },
                                            isEnabled: { availableCapabilities.contains($0) }) { capability in
                            HStack(spacing: 1) {
                                Text(capability.label)
                                if !isCompact && capability.isAvailableInDemo {
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
                .foregroundStyle(feedback.isRejected ? theme.colors.error : theme.colors.secondaryText)
                .lineLimit(1)
            HStack(spacing: 1) {
                if step.isCapabilities { Button("Back") { step = .language } }
                Button(step.actionTitle,
                       action: step.isLanguage ? continueToCapabilities : save)
                Button("Cancel", action: cancel)
            }
            Spacer(minLength: 0)
            if isShort {
                hints(isCompact: true)
            } else {
                StatusBar { hints(isCompact: isCompact) }
            }
        }
        .padding(.horizontal, isShort ? 0 : 1)
        .padding(.vertical, isShort ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .chioTheme(isShort ? theme.replacing(spacing: theme.spacing.replacing(sectionGap: 0)) : theme)
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
            switch feedback {
            case .saved(let saved):
                if saved != draft { feedback = .editing }
            case .editing, .rejected, .cancelled, .reset: break
            }
        }
    }
}

extension ChoiceExampleView.Step: Hashable {}
extension ChoiceExampleView.Step: Sendable {}
extension ChoiceExampleView.Feedback: Equatable {}
extension ChoiceExampleView.Feedback: Hashable {}
extension ChoiceExampleView.Feedback: Codable {}
extension ChoiceExampleView.Feedback: Sendable {}
