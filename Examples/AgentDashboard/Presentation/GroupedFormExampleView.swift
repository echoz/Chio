import Chio
import SwiftTUI

/// Grouped editing with one parent-owned draft and an explicit local save boundary.
@MainActor
struct GroupedFormExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var themeChoice: ExampleTheme
    @State private var draft: RunSettingsDraft
    @State private var savedDraft = RunSettingsDraft()
    @State private var validation = FormValidation<RunSettingsDraft.Field>()
    @State private var feedback = Feedback.editing
    @FocusState private var focus: RunSettingsDraft.Field?

    // A draft override supports layout probes; the saved baseline remains the defaults.
    init(theme: ExampleTheme = .default, initialDraft: RunSettingsDraft = .init()) {
        _themeChoice = State(wrappedValue: theme)
        _draft = State(wrappedValue: initialDraft)
    }

    private enum Feedback: Equatable { case editing, saved, rejected, cancelled }
    private var theme: ChioTheme { themeChoice.theme }
    private var short: Bool { terminalSize.height < 24 }

    private var name: Binding<String> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.name }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(name: $0)
        })
    }

    private var automaticRuns: Binding<Bool> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.automaticRuns }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(automaticRuns: $0)
        })
    }

    private var interval: Binding<String> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.intervalMinutes }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(intervalMinutes: $0)
        })
    }

    private var timeout: Binding<String> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.timeoutMinutes }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(timeoutMinutes: $0)
        })
    }

    private var status: String {
        if feedback == .rejected && !draft.issues.isEmpty { return "Not saved · check the fields" }
        if draft != savedDraft { return "Unsaved changes" }
        switch feedback {
        case .cancelled: return "Cancelled · saved values restored"
        case .saved: return "Saved locally · no jobs started"
        case .editing, .rejected: return "Local settings · no jobs started"
        }
    }

    private func save() {
        let current = draft
        let submission = validation.submitting(current.issues)
        validation = submission.validation
        if let invalid = submission.firstInvalidField {
            feedback = .rejected
            focus = invalid
        } else {
            savedDraft = current
            validation = FormValidation()
            feedback = .saved
        }
    }

    private func cancel() {
        draft = savedDraft
        validation = FormValidation()
        feedback = .cancelled
        focus = .name
    }

    private func revealFocusedError(using proxy: ScrollViewProxy) {
        if let focus, validation.message(for: focus, in: draft.issues) != nil {
            proxy.scrollTo(focus, anchor: .top)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 1) {
            GroupBox("Workspace") {
                VStack(alignment: .leading, spacing: 1) {
                    FormField("Workspace name", description: short ? "" : "Required · up to 32 characters",
                              error: validation.message(for: .name, in: draft.issues)) {
                        TextField("Workspace name", text: name)
                            .accessibilityLabel("Workspace name")
                            .focused($focus, equals: .name)
                    }
                    .id(RunSettingsDraft.Field.name)
                }
            }
            GroupBox("Automation") {
                VStack(alignment: .leading, spacing: 1) {
                    FormField("Automatic runs", description: short ? "" : "Settings only · no scheduler is started") {
                        Toggle("Automatic runs", isOn: automaticRuns)
                            .focused($focus, equals: .automaticRuns)
                    }
                    .id(RunSettingsDraft.Field.automaticRuns)
                    if draft.automaticRuns {
                        FormField("Interval (minutes)", description: short ? "" : "Whole minutes · 1–60",
                                  error: validation.message(for: .interval, in: draft.issues)) {
                            TextField("Interval", text: interval)
                                .accessibilityLabel("Interval")
                                .focused($focus, equals: .interval)
                        }
                        .id(RunSettingsDraft.Field.interval)
                        FormField("Timeout (minutes)", description: short ? "" : "Must be shorter than the interval",
                                  error: validation.message(for: .timeout, in: draft.issues)) {
                            TextField("Timeout", text: timeout)
                                .accessibilityLabel("Timeout")
                                .focused($focus, equals: .timeout)
                        }
                        .id(RunSettingsDraft.Field.timeout)
                    }
                }
            }
        }
        .padding(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hints: some View {
        KeyHints {
            KeyHint("tab/⇧tab", "focus")
            KeyHint("^S", "save")
            KeyHint("^X", "cancel")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }
}

extension GroupedFormExampleView: View {
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text("chio").bold().foregroundStyle(theme.colors.accent)
                    Text("/ grouped forms").foregroundStyle(theme.colors.secondaryText)
                }
                if !short {
                    Text("Run settings, kept together.").foregroundStyle(theme.colors.secondaryText)
                }
                ScrollView { fields }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text(status).foregroundStyle(feedback == .rejected && !draft.issues.isEmpty
                                             ? theme.colors.error : theme.colors.secondaryText)
                    .lineLimit(1)
                Text("Saved: \(savedDraft.summary)").foregroundStyle(theme.colors.mutedText).lineLimit(1)
                HStack(spacing: 1) {
                    Button("Save", action: save)
                    Button("Cancel", action: cancel)
                }
                if short { hints } else { StatusBar { hints } }
            }
            .padding(.horizontal, short ? 0 : 1)
            .padding(.vertical, short ? 0 : 1)
            .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
            .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
            .chioTheme(theme)
            .onAppear { focus = .name }
            .onSubmit(save)
            .onChange(of: focus) { old, new in
                // Restoring the saved draft is not a visit to the abandoned field.
                let restoringSavedFocus = feedback == .cancelled && draft == savedDraft && new == .name
                if !restoringSavedFocus {
                    if feedback == .cancelled { feedback = .editing }
                    if let old { validation = validation.recordingExit(from: old) }
                }
                revealFocusedError(using: proxy)
            }
            .onChange(of: validation) {
                revealFocusedError(using: proxy)
            }
            .onChange(of: terminalSize) {
                revealFocusedError(using: proxy)
            }
            .onChange(of: draft.automaticRuns) {
                if !draft.automaticRuns && (focus == .interval || focus == .timeout) {
                    focus = .automaticRuns
                }
            }
            .onKeyPress { press in
                guard press.modifiers == .ctrl else { return .ignored }
                switch press.key {
                case .character("s"): save()
                case .character("x"): cancel()
                case .character("t"): themeChoice = themeChoice.next
                case .character("q"): _ = requestTermination()
                default: return .ignored
                }
                return .handled
            }
        }
    }
}
