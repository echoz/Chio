import Chio
import SwiftTUI

/// A local simulation; the native controls own presentation and animation.
@MainActor
struct FeedbackExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var themeChoice: ExampleTheme
    @State private var phase = Phase.ready
    @State private var prompt: Prompt?
    @State private var showsToast = false

    init(theme: ExampleTheme = .default) {
        _themeChoice = State(wrappedValue: theme)
    }

    private enum Prompt: Equatable { case publish, discard }

    private enum Phase: Hashable {
        case ready, publishing, published

        var stage: Spinner.Stage {
            switch self {
            case .ready: .inactive
            case .publishing: .active
            case .published: .finished
            }
        }

        var label: String {
            switch self {
            case .ready: "Ready to publish"
            case .publishing: "Publishing report…"
            case .published: "Report published"
            }
        }
    }

    private var theme: ChioTheme { themeChoice.theme }

    private func publish() {
        guard phase != .publishing else { return }
        showsToast = false
        prompt = .publish
    }

    private func discard() {
        guard phase == .published else { return }
        showsToast = false
        prompt = .discard
    }

    private func isPresented(_ kind: Prompt) -> Binding<Bool> {
        let storage = $prompt
        return Binding(get: { storage.wrappedValue == kind }, set: { presented in
            if presented { storage.wrappedValue = kind }
            else if storage.wrappedValue == kind { storage.wrappedValue = nil }
        })
    }

    private var hints: some View {
        KeyHints {
            KeyHint("tab", "next")
            KeyHint("↵", "choose")
            KeyHint("esc", "dismiss")
            KeyHint("^P", "publish")
            KeyHint("^D", "discard")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }
}

extension FeedbackExampleView: View {
    var body: some View {
        let short = terminalSize.height < 24
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ confirmation & feedback").foregroundStyle(theme.colors.secondaryText)
            }
            if !short {
                Text("Small moments, considered details.").foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            GroupBox("Release report") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Chio · component showcase").bold()
                    Text("A local simulation. Nothing is sent.").foregroundStyle(theme.colors.secondaryText)
                    HStack(spacing: 1) {
                        Spinner(stage: phase.stage)
                        Text(phase.label).foregroundStyle(phase == .published ? theme.colors.success : theme.colors.foreground)
                    }
                }
            }
            HStack(spacing: 1) {
                Button("Publish", action: publish).disabled(phase == .publishing)
                Button("Discard", role: .destructive, action: discard).disabled(phase != .published)
            }
            if !short {
                Text("Publish asks first. Discard becomes available after completion.")
                    .foregroundStyle(theme.colors.mutedText)
            }
            Spacer(minLength: 0)
            if short { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, short ? 0 : 1)
        .padding(.vertical, short ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .confirmationDialog("Publish report?", isPresented: isPresented(.publish)) {
            Button("Cancel", role: .cancel) { prompt = nil }
            Button("Publish", role: .confirm) {
                prompt = nil
                phase = .publishing
            }
        } message: {
            Text("Preview a local publish with a spinner and completion toast.")
        }
        .alert("Discard report?", isPresented: isPresented(.discard)) {
            Button("Keep", role: .cancel) { prompt = nil }
            Button("Discard", role: .destructive) {
                prompt = nil
                phase = .ready
            }
        } message: {
            Text("Clear this simulated result and return to the ready state.")
        }
        .toast("Published · ready to share", isPresented: $showsToast,
               style: ChioToastStyle(theme: theme, tone: .success), duration: 3)
        .chioTheme(theme)
        .task(id: phase) {
            guard phase == .publishing else { return }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            guard !Task.isCancelled, phase == .publishing else { return }
            phase = .published
            showsToast = true
        }
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("t"): themeChoice = themeChoice.next
            case .character("q"): _ = requestTermination()
            case .character("p") where prompt == nil: publish()
            case .character("d") where prompt == nil: discard()
            default: return .ignored
            }
            return .handled
        }
    }
}
