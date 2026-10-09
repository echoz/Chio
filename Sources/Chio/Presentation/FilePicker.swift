import Foundation
import SwiftTUIViews

/// Chooses one existing, readable regular file using native search and focus.
///
/// `selection` changes only after explicit confirmation. Cancellation preserves
/// its previous value. The `.all` extension filter allows every file; `.only([])`
/// allows none. Extensions are matched case-insensitively without a leading dot, and
/// directories remain visible for navigation. Symlinks are followed while the
/// returned URL preserves the chosen path. The starting directory is not a sandbox.
/// Confirmation rechecks the file but does not open it or reserve its contents.
@MainActor
public struct FilePicker {
    private let initialDirectory: URL
    private let selection: Binding<URL?>
    private let allowedExtensions: FileExtensionFilter
    private let showsHiddenFiles: Bool
    private let confirm: @MainActor (URL) -> Void
    private let cancel: @MainActor () -> Void
    private let injectedOperations: Operations?

    @Environment(\.chioTheme) private var theme
    @State private var reader = FileDirectoryReader()
    @State private var phase = Phase.idle
    @State private var candidate: URL?
    @State private var query = ""

    public init(
        directory: URL,
        selection: Binding<URL?>,
        allowedExtensions: FileExtensionFilter = .all,
        showsHiddenFiles: Bool = false,
        onConfirm: @escaping @MainActor (URL) -> Void = { _ in },
        onCancel: @escaping @MainActor () -> Void = {}
    ) {
        self.init(directory: directory, selection: selection, allowedExtensions: allowedExtensions,
                  showsHiddenFiles: showsHiddenFiles, operations: nil, onConfirm: onConfirm, onCancel: onCancel)
    }

    // The effect boundary is replaceable internally for controlled lifecycle tests.
    init(
        directory: URL,
        selection: Binding<URL?>,
        allowedExtensions: FileExtensionFilter = .all,
        showsHiddenFiles: Bool = false,
        operations: Operations?,
        onConfirm: @escaping @MainActor (URL) -> Void = { _ in },
        onCancel: @escaping @MainActor () -> Void = {}
    ) {
        initialDirectory = directory
        self.selection = selection
        self.allowedExtensions = allowedExtensions
        self.showsHiddenFiles = showsHiddenFiles
        confirm = onConfirm
        cancel = onCancel
        injectedOperations = operations
    }

    struct Operations {
        let readDirectory: @Sendable (URL, Bool) async throws -> [FileEntry]
        let validateFile: @Sendable (URL) async throws -> URL
    }

    private struct Directory: Hashable, Codable, Sendable {
        let url: URL
        let entries: [FileEntry]
    }

    private enum Phase: Hashable, Codable, Sendable {
        case idle
        case loading(id: UUID, directory: URL, hidden: Bool)
        case browsing(Directory, error: String?)
        case confirming(id: UUID, directory: Directory, file: URL)
        case failed(directory: URL, message: String)
        case closed

        var requestID: UUID? {
            switch self {
            case .loading(let id, _, _), .confirming(let id, _, _): id
            case .idle, .browsing, .failed, .closed: nil
            }
        }

        var directory: URL? {
            switch self {
            case .loading(_, let url, _), .failed(let url, _): url
            case .browsing(let directory, _), .confirming(_, let directory, _): directory.url
            case .idle, .closed: nil
            }
        }

        var entries: [FileEntry] {
            switch self {
            case .browsing(let directory, _), .confirming(_, let directory, _): directory.entries
            case .idle, .loading, .failed, .closed: []
            }
        }

        var message: String {
            switch self {
            case .idle, .loading: "Loading folder…"
            case .browsing(let directory, let error): error ?? (directory.entries.isEmpty ? "This folder is empty." : "Choose one file.")
            case .confirming: "Checking file…"
            case .failed(_, let message): message
            case .closed: "Picker closed."
            }
        }

        var hasError: Bool {
            switch self {
            case .failed, .browsing(_, .some): true
            case .idle, .loading, .browsing(_, .none), .confirming, .closed: false
            }
        }
    }

    private func permittedEntries(in phase: Phase) -> [FileEntry] {
        phase.entries.filter { entry in
            entry.kind != .file || allowedExtensions.allows(entry.url.pathExtension)
        }
    }

    private func currentEntry(phase: Phase, candidate: URL?, query: String) -> FileEntry? {
        let visible = SearchMatcher.filtered(permittedEntries(in: phase), query: query,
                                             filter: .fuzzy, searchText: \.name)
        let id = SearchSelection.reconciled(candidate, visibleIDs: visible.map(\.id))
        return visible.first { $0.id == id }
    }

    private func navigate(to url: URL, phase: Binding<Phase>, candidate: Binding<URL?>, query: Binding<String>) {
        do {
            let directory = try FileDirectoryReader.normalizedLocation(url)
            phase.wrappedValue = .loading(id: UUID(), directory: directory, hidden: showsHiddenFiles)
        } catch {
            phase.wrappedValue = .failed(directory: url, message: error.localizedDescription)
        }
        candidate.wrappedValue = nil
        query.wrappedValue = ""
    }

    private func goUp(phase: Binding<Phase>, candidate: Binding<URL?>, query: Binding<String>) {
        guard let directory = phase.wrappedValue.directory, directory.path != "/" else { return }
        navigate(to: directory.deletingLastPathComponent(), phase: phase, candidate: candidate, query: query)
    }

    private func choose(phase: Binding<Phase>, candidate: Binding<URL?>, query: Binding<String>, activating: URL? = nil) {
        guard case .browsing(let directory, _) = phase.wrappedValue,
              let entry = currentEntry(phase: phase.wrappedValue, candidate: candidate.wrappedValue, query: query.wrappedValue),
              activating == nil || activating == entry.id else { return }
        switch entry.kind {
        case .directory:
            navigate(to: entry.url, phase: phase, candidate: candidate, query: query)
        case .file:
            candidate.wrappedValue = entry.id
            phase.wrappedValue = .confirming(id: UUID(), directory: directory, file: entry.url)
        case .other, .unavailable:
            phase.wrappedValue = .browsing(directory, error: "This entry cannot be selected.")
        }
    }

    private func cancel(phase: Binding<Phase>) {
        guard phase.wrappedValue != .closed else { return }
        phase.wrappedValue = .closed
        cancel()
    }

    @ViewBuilder
    private func row(_ entry: FileEntry) -> some View {
        HStack(spacing: 1) {
            Text(entry.kind == .directory ? "▸" : entry.isSymbolicLink ? "↗" : "·")
                .foregroundStyle(entry.kind == .directory ? theme.colors.accent : theme.colors.mutedText)
            Text(verbatim: entry.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Text(entry.kind == .directory ? "folder" : entry.isSymbolicLink ? "link" : entry.kind == .file ? "" : "unavailable")
                .foregroundStyle(theme.colors.mutedText).lineLimit(1)
        }
        .foregroundStyle(entry.kind == .other || entry.kind == .unavailable ? theme.colors.mutedText : theme.colors.foreground)
    }
}

extension FilePicker: View {
    public var body: some View {
        // Retain the exact native state owner across awaits and delayed handlers.
        let phaseStorage = $phase
        let candidateValue = $candidate
        let queryValue = $query
        let candidateStorage = Binding<URL?>(get: { candidateValue.wrappedValue }, set: { value in
            if case .confirming(_, let directory, let file) = phaseStorage.wrappedValue, value != file {
                phaseStorage.wrappedValue = .browsing(directory, error: nil)
            }
            candidateValue.wrappedValue = value
        })
        let queryStorage = Binding<String>(get: { queryValue.wrappedValue }, set: { value in
            // Invalidate before editing, so a later confirmation in the same
            // input batch is not cancelled by a delayed onChange callback.
            if value != queryValue.wrappedValue, case .confirming(_, let directory, _) = phaseStorage.wrappedValue {
                phaseStorage.wrappedValue = .browsing(directory, error: nil)
            }
            queryValue.wrappedValue = value
        })
        let pending = phase
        let reader = reader
        let operations = injectedOperations ?? Operations(
            readDirectory: { try await reader.readDirectory(at: $0, showsHiddenFiles: $1) },
            validateFile: { try await reader.validateFile(at: $0) }
        )
        let entry = currentEntry(phase: phase, candidate: candidate, query: query)
        let canChoose: Bool = if case .browsing = phase { entry?.kind == .file } else { false }
        let failed: Bool = if case .failed = phase { true } else { false }

        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: (phase.directory ?? initialDirectory).path)
                .foregroundStyle(theme.colors.secondaryText).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 1) {
                Spinner(stage: phase.requestID == nil ? .inactive : .active)
                Text(verbatim: phase.message)
                    .foregroundStyle(phase.hasError ? theme.colors.error : theme.colors.mutedText).lineLimit(2)
            }
            SearchableList(permittedEntries(in: phase), selection: candidateStorage, query: queryStorage,
                           prompt: "Filter files…", searchText: \.name, rowContent: row)
                .onActivate { item in
                    choose(phase: phaseStorage, candidate: candidateStorage, query: queryStorage, activating: item.id)
                }
                .onResultKeyPress { press in
                    guard press.modifiers.isEmpty, press.key == .backspace else { return .ignored }
                    goUp(phase: phaseStorage, candidate: candidateStorage, query: queryStorage)
                    return .handled
                }
                .disabled(phase == .closed)
            HStack(spacing: 1) {
                Button("Parent") { goUp(phase: phaseStorage, candidate: candidateStorage, query: queryStorage) }
                    .disabled(phase.directory == nil || phase.directory?.path == "/")
                Button(failed ? "Retry" : "Choose") {
                    if case .failed(let directory, _) = phaseStorage.wrappedValue {
                        navigate(to: directory, phase: phaseStorage, candidate: candidateStorage, query: queryStorage)
                    } else {
                        choose(phase: phaseStorage, candidate: candidateStorage, query: queryStorage)
                    }
                }
                .disabled(!failed && !canChoose)
                Button("Cancel", role: .cancel) { cancel(phase: phaseStorage) }.disabled(phase == .closed)
            }
            KeyHints {
                KeyHint("↑↓", "navigate")
                KeyHint("↵", "open/choose")
                KeyHint("/", "filter")
                KeyHint("⌫", "parent")
                KeyHint("^G", "cancel")
            }
        }
        .onAppear {
            navigate(to: initialDirectory, phase: phaseStorage, candidate: candidateStorage, query: queryStorage)
        }
        .onDisappear { phaseStorage.wrappedValue = .closed }
        .onChange(of: initialDirectory) {
            guard phaseStorage.wrappedValue != .closed else { return }
            navigate(to: initialDirectory, phase: phaseStorage, candidate: candidateStorage, query: queryStorage)
        }
        .onChange(of: showsHiddenFiles) {
            guard let directory = phaseStorage.wrappedValue.directory else { return }
            navigate(to: directory, phase: phaseStorage, candidate: candidateStorage, query: queryStorage)
        }
        .onChange(of: allowedExtensions) {
            // A changed policy invalidates an in-flight confirmation immediately
            // when the new configuration's lifecycle callback is applied.
            if case .confirming(_, let directory, _) = phaseStorage.wrappedValue {
                phaseStorage.wrappedValue = .browsing(directory, error: nil)
            }
        }
        .onKeyPress { press in
            guard press.modifiers == .ctrl, press.key == .character("g") else { return .ignored }
            cancel(phase: phaseStorage)
            return .handled
        }
        .task(id: pending.requestID) {
            guard let id = pending.requestID else { return }
            do {
                switch pending {
                case .loading(_, let directory, let hidden):
                    let entries = try await operations.readDirectory(directory, hidden)
                    guard !Task.isCancelled, phaseStorage.wrappedValue.requestID == id else { return }
                    phaseStorage.wrappedValue = .browsing(Directory(url: directory, entries: entries), error: nil)
                case .confirming(_, let directory, let file):
                    let url = try await operations.validateFile(file)
                    guard !Task.isCancelled, phaseStorage.wrappedValue.requestID == id else { return }
                    guard currentEntry(phase: phaseStorage.wrappedValue, candidate: candidateStorage.wrappedValue,
                                       query: queryStorage.wrappedValue)?.id == file else {
                        phaseStorage.wrappedValue = .browsing(directory, error: nil)
                        return
                    }
                    selection.wrappedValue = url
                    guard selection.wrappedValue == url else {
                        phaseStorage.wrappedValue = .browsing(directory, error: "The selection was not accepted.")
                        return
                    }
                    phaseStorage.wrappedValue = .closed
                    confirm(url)
                case .idle, .browsing, .failed, .closed: break
                }
            } catch {
                guard !Task.isCancelled, phaseStorage.wrappedValue.requestID == id else { return }
                switch pending {
                case .loading(_, let directory, _):
                    phaseStorage.wrappedValue = .failed(directory: directory, message: error.localizedDescription)
                case .confirming(_, let directory, _):
                    phaseStorage.wrappedValue = .browsing(directory, error: error.localizedDescription)
                case .idle, .browsing, .failed, .closed: break
                }
            }
        }
    }
}

extension FilePicker.Operations: Sendable {}
