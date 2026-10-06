import Chio
import Foundation
import SwiftTUI

@MainActor
struct TextEntryExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var themeChoice: ExampleTheme
    @State private var password: String
    @State private var notes: String
    @State private var showsValidation: Bool
    @State private var inputsDisabled: Bool
    @State private var feedback = Feedback.editing
    @FocusState private var focus: Field?

    init(theme: ExampleTheme = .default, initialPassword: String = "", initialNotes: String = "",
         showsValidation: Bool = false, inputsDisabled: Bool = false) {
        _themeChoice = State(wrappedValue: theme)
        _password = State(wrappedValue: initialPassword)
        _notes = State(wrappedValue: initialNotes)
        _showsValidation = State(wrappedValue: showsValidation)
        _inputsDisabled = State(wrappedValue: inputsDisabled)
    }

    private enum Field: Hashable { case password, notes }
    private enum Feedback: Equatable {
        case editing, rejected, cancelled
        case saved(notes: String)

        var message: String {
            switch self {
            case .editing: "Local sample · nothing persisted"
            case .rejected: "Not saved · check the fields"
            case .saved: "Accepted · password cleared"
            case .cancelled: "Cancelled · fields cleared"
            }
        }
    }

    private var isSaved: Bool {
        if case .saved = feedback { return true }
        return false
    }

    private var theme: ChioTheme { themeChoice.theme }
    private var passwordError: String? { password.count < 8 ? "Use at least 8 characters." : nil }
    private var notesError: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter some notes." : nil
    }

    private func save() {
        guard !inputsDisabled else { return }
        showsValidation = true
        if passwordError != nil {
            feedback = .rejected
            focus = .password
        } else if notesError != nil {
            feedback = .rejected
            focus = .notes
        } else {
            password = ""
            showsValidation = false
            feedback = .saved(notes: notes)
        }
    }

    private func cancel() {
        password = ""
        notes = ""
        showsValidation = false
        feedback = .cancelled
        if !inputsDisabled { focus = .password }
    }

    private func toggleDisabled() {
        inputsDisabled.toggle()
        if !inputsDisabled { focus = .password }
    }

    private var hints: some View {
        KeyHints {
            KeyHint("tab", "next")
            KeyHint("↵", "newline")
            KeyHint("^S", "save")
            KeyHint("^X", "cancel")
            KeyHint("^D", inputsDisabled ? "unlock" : "lock")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }
}

extension TextEntryExampleView: View {
    var body: some View {
        let short = terminalSize.height < 24
        let editorHeight = short ? 4 : min(10, max(5, terminalSize.height - 20))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ text entry").foregroundStyle(theme.colors.secondaryText)
            }
            if !short {
                Text("Local sample · use a made-up password")
                    .foregroundStyle(theme.colors.secondaryText)
            }
            FormField("Demo password", description: short ? "" : "Made-up value only · at least 8 characters",
                      error: showsValidation ? passwordError : nil) {
                SecureField("Made-up password", text: $password)
                    .accessibilityLabel("Demo password")
                    .focused($focus, equals: .password)
                    .disabled(inputsDisabled)
            }
            FormField("Notes", description: short ? "" : "Required · Return inserts a newline",
                      error: showsValidation ? notesError : nil) {
                TextEditor(text: $notes)
                    .accessibilityLabel("Notes")
                    .focused($focus, equals: .notes)
                    .disabled(inputsDisabled)
                    .frame(height: editorHeight)
            }
            if !short || isSaved || feedback == .cancelled || inputsDisabled {
                Text(inputsDisabled ? "Inputs locked · ^D unlock" : feedback.message)
                    .foregroundStyle(feedback == .rejected ? theme.colors.error : theme.colors.secondaryText)
                    .lineLimit(1)
            }
            HStack(spacing: 1) {
                Button("Save", action: save).disabled(inputsDisabled)
                Button("Cancel", action: cancel)
            }
            Spacer(minLength: 0)
            if short { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, short ? 0 : 1)
        .padding(.vertical, short ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .chioTheme(theme)
        .onAppear { if !inputsDisabled { focus = .password } }
        .onChange(of: password) {
            if case .saved = feedback, !password.isEmpty { feedback = .editing }
        }
        .onChange(of: notes) {
            if case .saved(let acceptedNotes) = feedback, notes != acceptedNotes { feedback = .editing }
        }
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("s"): save()
            case .character("x"): cancel()
            case .character("d"): toggleDisabled()
            case .character("t"): themeChoice = themeChoice.next
            case .character("q"): _ = requestTermination()
            default: return .ignored
            }
            return .handled
        }
    }
}
