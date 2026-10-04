import Chio
import Foundation
import SwiftTUI

@MainActor
struct FileSelectionExampleView {
    let directory: URL
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var isLight: Bool
    @State private var selection: URL?
    @State private var phase = Phase.choosing

    init(directory: URL, light: Bool = false) {
        self.directory = directory
        _isLight = State(wrappedValue: light)
    }

    private var theme: ChioTheme { isLight ? .light : .default }
    private enum Phase: Equatable { case choosing, confirmed, cancelled }
    private var isChoosing: Bool { phase == .choosing }

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
        let short = terminalSize.height < 24
        let phaseStorage = $phase
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ file selection").foregroundStyle(theme.colors.secondaryText)
            }
            if !short {
                Text("Browse a folder. Confirm a file.").foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            if isChoosing {
                FilePicker(directory: directory, selection: $selection, onConfirm: { _ in
                    guard phaseStorage.wrappedValue == .choosing else { return }
                    phaseStorage.wrappedValue = .confirmed
                }, onCancel: {
                    guard phaseStorage.wrappedValue == .choosing else { return }
                    phaseStorage.wrappedValue = .cancelled
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GroupBox("File choice") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(phase == .cancelled ? "Cancelled" : "Selected file")
                            .bold().foregroundStyle(phase == .cancelled ? theme.colors.secondaryText : theme.colors.success)
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
            if short { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, short ? 0 : 1)
        .padding(.vertical, short ? 0 : 1)
        .frame(maxWidth: 90, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .chioTheme(theme)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("t"): isLight.toggle()
            case .character("q"): _ = requestTermination()
            case .character("o") where phaseStorage.wrappedValue != .choosing:
                phaseStorage.wrappedValue = .choosing
            default: return .ignored
            }
            return .handled
        }
    }
}
