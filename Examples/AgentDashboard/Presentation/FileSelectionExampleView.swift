import Chio
import Foundation
import SwiftTUI

@MainActor
struct FileSelectionExampleView {
    let directory: URL
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var themeChoice: ExampleTheme
    @State private var selection: URL?
    @State private var phase = Phase.choosing

    init(directory: URL, theme: ExampleTheme = .default) {
        self.directory = directory
        _themeChoice = State(wrappedValue: theme)
    }

    private var theme: ChioTheme { themeChoice.theme }
    private enum Phase: Equatable {
        case choosing, confirmed, cancelled

        var isChoosing: Bool {
            switch self {
            case .choosing: true
            case .confirmed, .cancelled: false
            }
        }
        var resultTitle: String {
            switch self {
            case .choosing, .confirmed: "Selected file"
            case .cancelled: "Cancelled"
            }
        }
        func resultColor(in theme: ChioTheme) -> Color {
            switch self {
            case .choosing, .confirmed: theme.colors.success
            case .cancelled: theme.colors.secondaryText
            }
        }
    }
    private var isChoosing: Bool { phase.isChoosing }

    private var hints: some View {
        KeyHints {
            if !isChoosing {
                KeyHint("^O", "reopen")
            }
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }
}

extension FileSelectionExampleView: View {
    var body: some View {
        let isShort = terminalSize.height < 24
        let phaseStorage = $phase
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ file selection").foregroundStyle(theme.colors.secondaryText)
            }
            if !isShort {
                Text("Browse a folder. Confirm a file.").foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            if isChoosing {
                FilePicker(directory: directory, selection: $selection, onConfirm: { _ in
                    guard phaseStorage.wrappedValue.isChoosing else { return }
                    phaseStorage.wrappedValue = .confirmed
                }, onCancel: {
                    guard phaseStorage.wrappedValue.isChoosing else { return }
                    phaseStorage.wrappedValue = .cancelled
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GroupBox("File choice") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(phase.resultTitle)
                            .bold().foregroundStyle(phase.resultColor(in: theme))
                        if let selection {
                            Text(selection.lastPathComponent).bold()
                            Text(selection.path).foregroundStyle(theme.colors.secondaryText)
                        } else {
                            Text("No file selected.").foregroundStyle(theme.colors.secondaryText)
                        }
                    }
                }
                Button("Choose another file") { phaseStorage.wrappedValue = .choosing }
                Spacer(minLength: 0)
            }
            if isShort { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, isShort ? 0 : 1)
        .padding(.vertical, isShort ? 0 : 1)
        .frame(maxWidth: 90, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .chioTheme(theme)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("t"): themeChoice = themeChoice.next
            case .character("q"): _ = requestTermination()
            case .character("o") where !phaseStorage.wrappedValue.isChoosing:
                phaseStorage.wrappedValue = .choosing
            default: return .ignored
            }
            return .handled
        }
    }
}
