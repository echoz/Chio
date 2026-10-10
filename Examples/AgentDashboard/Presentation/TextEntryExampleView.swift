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
    @State private var areInputsDisabled: Bool
    @State private var feedback = Feedback.editing
    @FocusState private var focus: Field?

    init(theme: ExampleTheme = .default, initialPassword: String = "", initialNotes: String = "",
         showsValidation: Bool = false, areInputsDisabled: Bool = false) {
        _themeChoice = State(wrappedValue: theme)
        _password = State(wrappedValue: initialPassword)
        _notes = State(wrappedValue: initialNotes)
        _showsValidation = State(wrappedValue: showsValidation)
        _areInputsDisabled = State(wrappedValue: areInputsDisabled)
    }

    private enum Field: Hashable { case password, notes }
    private enum Feedback: Equatable {
        case editing, rejected, cancelled
        case saved(notes: String)

        var isRejected: Bool {
            switch self {
            case .rejected: true
            case .editing, .saved, .cancelled: false
            }
        }
        var isCancelled: Bool {
            switch self {
            case .cancelled: true
            case .editing, .saved, .rejected: false
            }
        }

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
        switch feedback {
        case .saved: true
        case .editing, .rejected, .cancelled: false
        }
    }

    private var theme: ChioTheme { themeChoice.theme }
    private var passwordError: String? { password.count < 8 ? "Use at least 8 characters." : nil }
    private var notesError: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter some notes." : nil
    }

    private func save() {
        guard !areInputsDisabled else { return }
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
        if !areInputsDisabled { focus = .password }
    }

    private func toggleDisabled() {
        areInputsDisabled.toggle()
        if !areInputsDisabled { focus = .password }
    }

    private var hints: some View {
        KeyHints {
            KeyHint("tab", "next")
            KeyHint("↵", "newline")
            KeyHint("^S", "save")
            KeyHint("^X", "cancel")
            KeyHint("^D", areInputsDisabled ? "unlock" : "lock")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }
}

extension TextEntryExampleView: View {
    var body: some View {
        let isShort = terminalSize.height < 24
        let editorHeight = isShort ? 4 : min(10, max(5, terminalSize.height - 20))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ text entry").foregroundStyle(theme.colors.secondaryText)
            }
            if !isShort {
                Text("Local sample · use a made-up password")
                    .foregroundStyle(theme.colors.secondaryText)
            }
            FormField("Demo password", description: isShort ? "" : "Made-up value only · at least 8 characters",
                      error: showsValidation ? passwordError : nil) {
                SecureField("Made-up password", text: $password)
                    .accessibilityLabel("Demo password")
                    .focused($focus, equals: .password)
                    .disabled(areInputsDisabled)
            }
            FormField("Notes", description: isShort ? "" : "Required · Return inserts a newline",
                      error: showsValidation ? notesError : nil) {
                TextEditor(text: $notes)
                    .accessibilityLabel("Notes")
                    .focused($focus, equals: .notes)
                    .disabled(areInputsDisabled)
                    .frame(height: editorHeight)
            }
            if !isShort || isSaved || feedback.isCancelled || areInputsDisabled {
                Text(areInputsDisabled ? "Inputs locked · ^D unlock" : feedback.message)
                    .foregroundStyle(feedback.isRejected ? theme.colors.error : theme.colors.secondaryText)
                    .lineLimit(1)
            }
            HStack(spacing: 1) {
                Button("Save", action: save).disabled(areInputsDisabled)
                Button("Cancel", action: cancel)
            }
            Spacer(minLength: 0)
            if isShort { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, isShort ? 0 : 1)
        .padding(.vertical, isShort ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .chioTheme(theme)
        .onAppear { if !areInputsDisabled { focus = .password } }
        .onChange(of: password) {
            switch feedback {
            case .saved:
                if !password.isEmpty { feedback = .editing }
            case .editing, .rejected, .cancelled: break
            }
        }
        .onChange(of: notes) {
            switch feedback {
            case .saved(let acceptedNotes):
                if notes != acceptedNotes { feedback = .editing }
            case .editing, .rejected, .cancelled: break
            }
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
