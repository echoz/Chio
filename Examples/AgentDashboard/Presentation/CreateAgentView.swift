import Chio
import SwiftTUI

@MainActor
struct CreateAgentView {
    @Binding var draft: AgentDraft
    @Binding var isLight: Bool
    @State private var validation = FormValidation<AgentDraft.Field>()
    @FocusState private var focus: Focus?
    let entry: Entry
    let validateOnArrival: Bool
    let create: @MainActor @Sendable () -> Void
    let cancel: @MainActor @Sendable () -> Void

    init(
        draft: Binding<AgentDraft>, isLight: Binding<Bool>,
        entry: Entry = .name, validateOnArrival: Bool = false,
        create: @escaping @MainActor @Sendable () -> Void,
        cancel: @escaping @MainActor @Sendable () -> Void
    ) {
        _draft = draft
        _isLight = isLight
        self.entry = entry
        self.validateOnArrival = validateOnArrival
        self.create = create
        self.cancel = cancel
    }

    enum Entry {
        case name
        case role
    }

    private enum Focus: Hashable {
        case name, role, suite, start, create, cancel

        var validatedField: AgentDraft.Field? {
            switch self {
            case .name: .name
            case .suite: .suite
            default: nil
            }
        }
    }

    private var theme: ChioTheme { isLight ? .light : .default }

    private var name: Binding<String> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.name }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(name: $0)
        })
    }

    private var role: Binding<AgentDraft.Role> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.role }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(role: $0)
        })
    }

    private var suite: Binding<String> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.suite }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(suite: $0)
        })
    }

    private var startImmediately: Binding<Bool> {
        let storage = $draft
        return Binding(get: { storage.wrappedValue.startImmediately }, set: {
            storage.wrappedValue = storage.wrappedValue.replacing(startImmediately: $0)
        })
    }

    private func validate() -> AgentDraft.Field? {
        let submission = validation.submitting(draft.issues)
        validation = submission.validation
        return submission.firstInvalidField
    }

    private func submit() {
        if let firstInvalid = validate() {
            focus = firstInvalid == .name ? .name : .suite
        } else {
            create()
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 1) {
            FormField("Name", description: "Required · up to 32 characters",
                      error: validation.message(for: .name, in: draft.issues)) {
                TextField("e.g. Release agent", text: name)
                    .accessibilityLabel("Agent name")
                    .focused($focus, equals: .name)
            }
            .id(AgentDraft.Field.name)

            FormField("Role", description: "← → choose what this agent does") {
                Picker("Role", selection: role) {
                    ForEach(AgentDraft.Role.allCases, id: \.self) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                .focused($focus, equals: .role)
            }

            if draft.role == .test {
                FormField("Test suite", description: "Required for Test · up to 40 characters",
                          error: validation.message(for: .suite, in: draft.issues)) {
                    TextField("e.g. Integration tests", text: suite)
                        .accessibilityLabel("Test suite")
                        .focused($focus, equals: .suite)
                }
                .id(AgentDraft.Field.suite)
            }

            FormField("Start immediately", description: "Space toggles · runs a local simulation") {
                Toggle("Start immediately", isOn: startImmediately)
                    .focused($focus, equals: .start)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension CreateAgentView: View {
    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("chio").bold().foregroundStyle(theme.colors.accent)
                        Text("/ create agent").foregroundStyle(theme.colors.secondaryText)
                    }
                    ScrollView {
                        fields
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    HStack(spacing: 2) {
                        Button("Create agent", action: submit)
                            .focused($focus, equals: .create)
                        Button("Cancel", action: cancel)
                            .focused($focus, equals: .cancel)
                    }
                    StatusBar {
                        KeyHints {
                            KeyHint("tab", "next")
                            KeyHint("^S", "create")
                            KeyHint("esc", "cancel")
                            KeyHint("^T", "theme")
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .frame(maxWidth: 64, maxHeight: .infinity, alignment: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .chioTheme(theme)
            }
            .onAppear {
                focus = entry == .role ? .role : .name
                if validateOnArrival, let firstInvalid = validate() {
                    focus = firstInvalid == .name ? .name : .suite
                }
            }
            .onSubmit(submit)
            .onKeyPress(.escape) { _ in
                cancel()
                return .handled
            }
            .onKeyPress { press in
                guard press.modifiers == .ctrl else { return .ignored }
                switch press.key {
                case .character("s"): submit()
                case .character("t"): isLight.toggle()
                default: return .ignored
                }
                return .handled
            }
            .onChange(of: focus) { old, _ in
                if let field = old?.validatedField { validation = validation.recordingExit(from: field) }
                if let field = focus?.validatedField {
                    proxy.scrollTo(field, anchor: .top)
                }
            }
            .onChange(of: validation) {
                if let field = focus?.validatedField {
                    proxy.scrollTo(field, anchor: .top)
                }
            }
            .onChange(of: draft.role) {
                if draft.role != .test && focus == .suite { focus = .role }
            }
        }
    }
}
