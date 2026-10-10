import Foundation
@testable import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct FilePickerTests {
    @Test("Browsing and fuzzy filtering preserve the committed binding; extension policy retains folders")
    func browsingAndFiltering() async throws {
        let gate = FilePickerOperationGate()
        try await withFilePickerScene(gate: gate, allowedExtensions: .only(["sWiFt"])) { session, _, recorder in
            _ = try await recorder.wait(description: "first directory read starts") { $0.pickerContains("R=1 V=0") }
            try await gate.finishRead(1, entries: [pickerEntry("Sources", .directory), pickerEntry("Alpha.SWIFT"),
                                                 pickerEntry("Beta.swift"), pickerEntry("Notes.txt")])
            let ready = try await recorder.wait(description: "folders and case-insensitive allowed files") {
                $0.pickerContains("Sources") && $0.pickerContains("Alpha.SWIFT") && $0.pickerHasResultsFocus
            }
            #expect(ready.pickerContains("Beta.swift"))
            #expect(!ready.pickerContains("Notes.txt"))
            #expect(ready.pickerContains("S=old W=0 C=0 X=0"))
            session.send(.key(.arrowDown))
            let highlighted = try await pickerBarrier(session, recorder)
            #expect(highlighted.pickerContains("S=old W=0 C=0 X=0"))
            session.sendInput(Array("/btw".utf8))
            let filtered = try await recorder.wait(description: "noncontiguous fuzzy query matches Beta.swift") {
                $0.pickerHasQuery("btw") && $0.pickerContains("1 of 3 items")
            }
            #expect(filtered.pickerContains("Beta.swift"))
            #expect(!filtered.pickerContains("Alpha.SWIFT"))
            #expect(filtered.pickerContains("S=old W=0 C=0 X=0"))
            session.sendInput(Array("zzz".utf8))
            let noMatches = try await recorder.wait(description: "no matches differs from an empty directory") {
                $0.pickerContains("No matches.")
            }
            #expect(noMatches.pickerContains("S=old W=0 C=0 X=0"))
            session.send(.key(.character("g"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "cancel preserves the binding") {
                $0.pickerContains("S=old W=0 C=0 X=1")
            }
            #expect(await gate.validationURLs.isEmpty)
        }
    }

    @Test("All extensions permits files; an empty restriction retains only directories", arguments: [false, true])
    func unrestrictedAndEmptyExtensionPolicies(emptyPolicy: Bool) async throws {
        let gate = FilePickerOperationGate()
        try await withFilePickerScene(gate: gate, allowedExtensions: emptyPolicy ? .only([]) : .all) { _, _, recorder in
            _ = try await recorder.wait(description: "policy directory read") { $0.pickerContains("R=1 V=0") }
            try await gate.finishRead(1, entries: [pickerEntry("Sources", .directory), pickerEntry("Any.data")])
            let listed = try await recorder.wait(description: "policy-filtered directory rows") {
                $0.pickerContains("Sources") && $0.pickerContains(emptyPolicy ? "1 of 1 item" : "2 of 2 items")
            }
            #expect(listed.pickerContains("Any.data") == !emptyPolicy)
            #expect(listed.pickerContains("S=old W=0 C=0 X=0"))
        }
    }

    @Test("An application binding that refuses the file keeps the picker open without confirming")
    func refusedSelection() async throws {
        let gate = FilePickerOperationGate()
        let file = pickerEntry("Refused.swift")
        try await withFilePickerScene(gate: gate, allowsSelection: false) { session, _, recorder in
            _ = try await recorder.wait(description: "binding refusal directory read") { $0.pickerContains("R=1 V=0") }
            try await gate.finishRead(1, entries: [file])
            _ = try await recorder.wait(description: "file ready") {
                $0.pickerContains("Refused.swift") && $0.pickerHasResultsFocus
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "file validation started") { $0.pickerContains("R=1 V=1") }
            try await gate.finishValidation(1, url: file.url)
            let refused = try await recorder.wait(description: "binding rejection remains visible in the picker") {
                $0.pickerContains("The selection was not accepted.") && $0.pickerContains("S=old W=1 C=0 X=0")
            }
            #expect(refused.pickerContains("Refused.swift"))
            #expect(refused.pickerButtonEnabled("Cancel"))
            session.send(.key(.character("g"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "rejected choice remains cancellable") {
                $0.pickerContains("S=old W=1 C=0 X=1")
            }
        }
    }

    @Test("Activating a directory browses it; Parent returns without choosing a file")
    func directoryNavigation() async throws {
        let gate = FilePickerOperationGate()
        let child = pickerRoot.appendingPathComponent("Sources", isDirectory: false)
        try await withFilePickerScene(gate: gate) { session, _, recorder in
            _ = try await recorder.wait(description: "root read") { $0.pickerContains("R=1 V=0") }
            try await gate.finishRead(1, entries: [pickerEntry("Sources", .directory), pickerEntry("Root.swift")])
            _ = try await recorder.wait(description: "root rows own focus") {
                $0.pickerContains("Sources") && $0.pickerHasResultsFocus
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "directory activation starts a new read") {
                $0.pickerContains("R=2 V=0")
            }
            #expect(await gate.readURLs == [pickerRoot, child])
            try await gate.finishRead(2, entries: [])
            let empty = try await recorder.wait(description: "empty child directory") {
                $0.pickerContains("This folder is empty.")
            }
            #expect(!empty.pickerContains("No matches."))
            #expect(empty.pickerContains("S=old W=0 C=0 X=0"))
            try await focusPickerButton("Parent", session, recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "Parent reads the root again") { $0.pickerContains("R=3 V=0") }
            #expect(await gate.readURLs.last == pickerRoot)
            try await gate.finishRead(3, entries: [pickerEntry("Root.swift")])
            _ = try await recorder.wait(description: "Parent restores root contents") { $0.pickerContains("Root.swift") }
            #expect(await gate.validationURLs.isEmpty)
        }
    }

    @Test("Read failures offer Retry and retain Parent and Cancel")
    func retryReadFailure() async throws {
        let gate = FilePickerOperationGate()
        try await withFilePickerScene(gate: gate) { session, _, recorder in
            _ = try await recorder.wait(description: "first read") { $0.pickerContains("R=1 V=0") }
            try await gate.failRead(1, message: "Folder is unavailable.")
            let failed = try await recorder.wait(description: "directory failure and retry action") {
                $0.pickerContains("Folder is unavailable.") && $0.pickerContains("Retry")
            }
            #expect(failed.pickerButtonEnabled("Retry"))
            #expect(failed.pickerButtonEnabled("Parent"))
            #expect(failed.pickerButtonEnabled("Cancel"))
            #expect(failed.pickerContains("S=old W=0 C=0 X=0"))
            try await focusPickerButton("Retry", session, recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "retry starts the same read") { $0.pickerContains("R=2 V=0") }
            #expect(await gate.readURLs == [pickerRoot, pickerRoot])
            try await gate.finishRead(2, entries: [pickerEntry("Recovered.swift")])
            _ = try await recorder.wait(description: "retry displays recovered contents") {
                $0.pickerContains("Recovered.swift") && !$0.pickerContains("Folder is unavailable.")
            }
        }
    }

    @Test("Return and Choose revalidate before committing exactly once", arguments: [false, true])
    func explicitConfirmation(chooseButton: Bool) async throws {
        let gate = FilePickerOperationGate()
        let file = pickerEntry("Chosen.swift")
        try await withFilePickerScene(gate: gate) { session, _, recorder in
            _ = try await recorder.wait(description: "directory read") { $0.pickerContains("R=1 V=0") }
            try await gate.finishRead(1, entries: [file])
            _ = try await recorder.wait(description: "file ready for confirmation") {
                $0.pickerContains("Chosen.swift") && $0.pickerHasResultsFocus
            }
            if chooseButton { try await focusPickerButton("Choose", session, recorder) }
            session.send(.key(.return))
            let pending = try await recorder.wait(description: "file validation is suspended") {
                $0.pickerContains("Checking file…") && $0.pickerContains("R=1 V=1")
            }
            #expect(pending.pickerContains("S=old W=0 C=0 X=0"))
            #expect(await gate.validationURLs == [file.url])
            session.send(.key(.return))
            let repeated = try await pickerBarrier(session, recorder)
            #expect(repeated.pickerContains("R=1 V=1"))
            #expect(repeated.pickerContains("S=old W=0 C=0 X=0"))
            try await gate.finishValidation(1, url: file.url)
            _ = try await recorder.wait(description: "validated file commits once") {
                $0.pickerContains("S=Chosen.swift W=1 C=1 X=0") && $0.pickerHasDismissedFocus
            }
            session.sendInput(Array("\r\r".utf8))
            let closed = try await pickerBarrier(session, recorder)
            #expect(closed.pickerContains("S=Chosen.swift W=1 C=1 X=0"))
            #expect(await gate.validationURLs.count == 1)
        }
    }

    @Test("A file deleted after listing is rejected by real confirmation revalidation")
    func deletedFileCannotCommit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Gone.swift")
        try Data("contents".utf8).write(to: file)
        try await withFilePickerScene(directory: directory) { session, _, recorder in
            _ = try await recorder.wait(description: "real file is listed and focused") {
                $0.pickerContains("Gone.swift") && $0.pickerHasResultsFocus
            }
            try FileManager.default.removeItem(at: file)
            session.send(.key(.return))
            let rejected = try await recorder.wait(description: "deleted file produces visible validation error") {
                $0.pickerContains("This location no longer exists.") && $0.pickerContains("S=old W=0 C=0 X=0")
            }
            #expect(rejected.pickerButtonEnabled("Cancel"))
            session.send(.key(.character("g"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "cancel after failed revalidation") {
                $0.pickerContains("S=old W=0 C=0 X=1")
            }
        }
    }

    @Test("Both themes retain search, actions and keyboard help at 36 by 18", arguments: [false, true])
    func narrowThemes(light: Bool) async throws {
        let gate = FilePickerOperationGate()
        try await withFilePickerScene(gate: gate, light: light, width: 36, height: 18) { session, _, recorder in
            _ = try await recorder.wait(description: "narrow directory read") { $0.pickerContains("R=1 V=0") }
            try await gate.finishRead(1, entries: [pickerEntry("Sample.swift")])
            let ready = try await recorder.wait(description: "narrow themed file row") {
                $0.pickerContains("Sample.swift") && $0.pickerHasResultsFocus
            }
            #expect(ready.pickerHasQuery(""))
            #expect(ready.pickerContains("Parent"))
            #expect(ready.pickerContains("Choose"))
            #expect(ready.pickerContains("Cancel"))
            #expect(ready.pickerContains("filter"))
            #expect(ready.pickerContains("cancel"))
            session.sendInput(Array("/smw".utf8))
            _ = try await recorder.wait(description: "narrow filter remains usable") {
                $0.pickerHasQuery("smw") && $0.pickerContains("Sample.swift")
            }
            session.send(.key(.character("g"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "narrow cancel remains usable") {
                $0.pickerContains("S=old W=0 C=0 X=1")
            }
        }
    }

    @Test("Normalized dot components identify the root and disable Parent")
    func normalizedRoot() async throws {
        let gate = FilePickerOperationGate()
        let directory = URL(fileURLWithPath: "/picker/initial/../..")
        try await withFilePickerScene(directory: directory, gate: gate) { _, _, recorder in
            _ = try await recorder.wait(description: "normalized root read starts") { $0.pickerContains("R=1 V=0") }
            #expect(await gate.readURLs == [URL(fileURLWithPath: "/")])
            try await gate.finishRead(1, entries: [])
            let root = try await recorder.wait(description: "root listing has disabled Parent") {
                $0.pickerContains("This folder is empty.")
            }
            #expect(!root.pickerButtonEnabled("Parent"))
            #expect(root.pickerButtonEnabled("Cancel"))
        }
    }

    @Test("Changing the query and confirming in one batch supersedes an earlier validation")
    func batchedReplacementConfirmation() async throws {
        let gate = FilePickerOperationGate()
        let alpha = pickerEntry("Alpha.swift")
        let beta = pickerEntry("Beta.swift")
        try await withFilePickerScene(gate: gate) { session, _, recorder in
            _ = try await recorder.wait(description: "directory read") { $0.pickerContains("R=1 V=0") }
            try await gate.finishRead(1, entries: [alpha, beta])
            _ = try await recorder.wait(description: "Alpha is ready") {
                $0.pickerContains("Alpha.swift") && $0.pickerHasResultsFocus
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "Alpha confirmation pending") { $0.pickerContains("R=1 V=1") }
            session.sendInput(Array("/btw\r\r".utf8))
            _ = try await recorder.wait(description: "same batch starts a new Beta confirmation") {
                $0.pickerHasQuery("btw") && $0.pickerContains("R=1 V=2")
            }
            #expect(await gate.validationURLs == [alpha.url, beta.url])
            try await gate.finishValidation(1, url: alpha.url)
            _ = try await recorder.wait(description: "superseded Alpha validation returns") { $0.pickerContains("D=2") }
            let stale = try await pickerBarrier(session, recorder)
            #expect(stale.pickerContains("S=old W=0 C=0 X=0"))
            try await gate.finishValidation(2, url: beta.url)
            _ = try await recorder.wait(description: "replacement Beta confirmation commits once") {
                $0.pickerContains("S=Beta.swift W=1 C=1 X=0")
            }
        }
    }

    @Test("A late read cannot replace the directory reached with Parent")
    func staleReadAfterNavigation() async throws {
        let gate = FilePickerOperationGate()
        try await withFilePickerScene(gate: gate) { session, _, recorder in
            _ = try await recorder.wait(description: "A read is suspended") { $0.pickerContains("R=1 V=0") }
            try await focusPickerButton("Parent", session, recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "Parent starts B read before A finishes") {
                $0.pickerContains("R=2 V=0")
            }
            #expect(await gate.readURLs == [pickerRoot, URL(fileURLWithPath: "/picker", isDirectory: false)])
            try await gate.finishRead(2, entries: [pickerEntry("Current.swift")])
            _ = try await recorder.wait(description: "B contents arrive first") { $0.pickerContains("Current.swift") }
            try await gate.finishRead(1, entries: [pickerEntry("Stale.swift")])
            _ = try await recorder.wait(description: "both reads have returned") { $0.pickerContains("D=2") }
            let after = try await pickerBarrier(session, recorder)
            #expect(after.pickerContains("Current.swift"))
            #expect(!after.pickerContains("Stale.swift"))
            #expect(after.pickerContains("S=old W=0 C=0 X=0"))
        }
    }

    @Test("A read from a cancelled opening cannot replace the reopened picker")
    func staleReadAfterReopening() async throws {
        let gate = FilePickerOperationGate()
        try await withFilePickerScene(gate: gate) { session, _, recorder in
            _ = try await recorder.wait(description: "first opening read is suspended") { $0.pickerContains("R=1 V=0") }
            session.send(.key(.character("g"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "first opening cancelled and host focus restored") {
                $0.pickerContains("X=1") && $0.pickerHasDismissedFocus
            }
            session.send(.key(.character("o"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "reopening starts a fresh read") { $0.pickerContains("R=2 V=0") }
            try await gate.finishRead(2, entries: [pickerEntry("Reopened.swift")])
            _ = try await recorder.wait(description: "reopened contents") { $0.pickerContains("Reopened.swift") }
            try await gate.finishRead(1, entries: [pickerEntry("Cancelled.swift")])
            _ = try await recorder.wait(description: "cancelled read returns late") { $0.pickerContains("D=2") }
            let after = try await pickerBarrier(session, recorder)
            #expect(after.pickerContains("Reopened.swift"))
            #expect(!after.pickerContains("Cancelled.swift"))
            #expect(after.pickerContains("S=old W=0 C=0 X=1"))
        }
    }

    @Test("Late validation does not commit after cancellation, navigation or a changed candidate",
          arguments: PickerValidationInterruption.allCases)
    fileprivate func staleValidation(interruption: PickerValidationInterruption) async throws {
        let gate = FilePickerOperationGate()
        let first = pickerEntry("Alpha.swift")
        try await withFilePickerScene(gate: gate) { session, _, recorder in
            _ = try await recorder.wait(description: "directory read") { $0.pickerContains("R=1 V=0") }
            try await gate.finishRead(1, entries: [first, pickerEntry("Beta.swift")])
            _ = try await recorder.wait(description: "files ready") {
                $0.pickerContains("Alpha.swift") && $0.pickerHasResultsFocus
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "Alpha validation is suspended") { $0.pickerContains("R=1 V=1") }
            switch interruption {
            case .cancel:
                session.send(.key(.character("g"), modifiers: .ctrl))
                _ = try await recorder.wait(description: "cancel precedes validation completion and restores host focus") {
                    $0.pickerContains("X=1") && $0.pickerHasDismissedFocus
                }
            case .parent:
                try await focusPickerButton("Parent", session, recorder)
                session.send(.key(.return))
                _ = try await recorder.wait(description: "navigation supersedes validation") { $0.pickerContains("R=2 V=1") }
                try await gate.finishRead(2, entries: [pickerEntry("Parent.swift")])
                _ = try await recorder.wait(description: "parent listing arrives") { $0.pickerContains("Parent.swift") }
            case .selection:
                session.send(.key(.arrowDown))
                _ = try await recorder.wait(description: "native row navigation changes the validation candidate") {
                    $0.raster.lines.contains { $0.contains("Beta.swift") && $0.contains("›") }
                }
            case .filter:
                session.sendInput(Array("/btw".utf8))
                _ = try await recorder.wait(description: "filter changes candidate during validation") {
                    $0.pickerHasQuery("btw") && $0.pickerContains("Beta.swift") && !$0.pickerContains("Alpha.swift")
                }
            }
            try await gate.finishValidation(1, url: first.url)
            let completionCount = interruption == .parent ? 3 : 2
            _ = try await recorder.wait(description: "superseded validation returns") {
                $0.pickerContains("D=\(completionCount)")
            }
            let after = try await pickerBarrier(session, recorder)
            #expect(after.pickerContains("S=old W=0 C=0"))
        }
    }
}

private enum PickerValidationInterruption: CaseIterable, Sendable {
    case cancel
    case parent
    case selection
    case filter
}

private let pickerRoot = URL(fileURLWithPath: "/picker/initial", isDirectory: false)

private func pickerEntry(_ name: String, _ kind: FileEntry.Kind = .file) -> FileEntry {
    FileEntry(url: pickerRoot.appendingPathComponent(name, isDirectory: kind == .directory),
              kind: kind, isSymbolicLink: false)
}

/// Continuations intentionally ignore cancellation so tests exercise stale outcomes,
/// rather than depending on a cooperative filesystem operation to discard them.
private actor FilePickerOperationGate {
    private var reads: [Int: CheckedContinuation<[FileEntry], any Error>] = [:]
    private var validations: [Int: CheckedContinuation<URL, any Error>] = [:]
    private var closed = false
    private(set) var readURLs: [URL] = []
    private(set) var validationURLs: [URL] = []

    func read(_ url: URL, onStart: @escaping @MainActor @Sendable () -> Void) async throws -> [FileEntry] {
        guard !closed else { throw CancellationError() }
        readURLs.append(url)
        let ordinal = readURLs.count
        return try await withCheckedThrowingContinuation { continuation in
            reads[ordinal] = continuation
            // The hosted readiness frame is emitted only after storing the gate.
            Task { @MainActor in onStart() }
        }
    }

    func validate(_ url: URL, onStart: @escaping @MainActor @Sendable () -> Void) async throws -> URL {
        guard !closed else { throw CancellationError() }
        validationURLs.append(url)
        let ordinal = validationURLs.count
        return try await withCheckedThrowingContinuation { continuation in
            validations[ordinal] = continuation
            Task { @MainActor in onStart() }
        }
    }

    func finishRead(_ ordinal: Int, entries: [FileEntry]) throws {
        let continuation = reads.removeValue(forKey: ordinal)
        let pending = try #require(continuation)
        pending.resume(returning: entries)
    }

    func failRead(_ ordinal: Int, message: String) throws {
        let continuation = reads.removeValue(forKey: ordinal)
        let pending = try #require(continuation)
        pending.resume(throwing: PickerTestFailure(message: message))
    }

    func finishValidation(_ ordinal: Int, url: URL) throws {
        let continuation = validations.removeValue(forKey: ordinal)
        let pending = try #require(continuation)
        pending.resume(returning: url)
    }

    func shutdown() {
        closed = true
        let pendingReads = Array(reads.values)
        let pendingValidations = Array(validations.values)
        reads.removeAll()
        validations.removeAll()
        for pending in pendingReads { pending.resume(throwing: CancellationError()) }
        for pending in pendingValidations { pending.resume(throwing: CancellationError()) }
    }
}

private struct PickerTestFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct FilePickerTestApp {
    let directory: URL
    let gate: FilePickerOperationGate?
    let allowedExtensions: FileExtensionFilter
    let allowsSelection: Bool
    let light: Bool

    nonisolated init() {
        directory = pickerRoot
        gate = nil
        allowedExtensions = .all
        allowsSelection = true
        light = false
    }

    nonisolated init(directory: URL, gate: FilePickerOperationGate?, allowedExtensions: FileExtensionFilter, allowsSelection: Bool, light: Bool) {
        self.directory = directory
        self.gate = gate
        self.allowedExtensions = allowedExtensions
        self.allowsSelection = allowsSelection
        self.light = light
    }
}

extension FilePickerTestApp: App {
    var body: some Scene {
        WindowGroup(id: "file-picker-tests") {
            FilePickerTestView(directory: directory, gate: gate, allowedExtensions: allowedExtensions,
                               allowsSelection: allowsSelection, light: light)
        }.exitOnKeys([])
    }
}

@MainActor
private struct FilePickerTestView {
    let directory: URL
    let gate: FilePickerOperationGate?
    let allowedExtensions: FileExtensionFilter
    let allowsSelection: Bool
    let light: Bool
    @State private var selection: URL? = URL(fileURLWithPath: "/previous/old")
    @State private var writes = 0
    @State private var confirmations = 0
    @State private var cancellations = 0
    @State private var presented = true
    @State private var reads = 0
    @State private var validations = 0
    @State private var completed = 0
    @State private var barrier = 0
    @FocusState private var dismissedFocused: Bool
}

extension FilePickerTestView: View {
    var body: some View {
        let selectionStorage = $selection
        let writesStorage = $writes
        let readsStorage = $reads
        let validationsStorage = $validations
        let completedStorage = $completed
        let operations = gate.map { gate in
            FilePicker.Operations(
                readDirectory: { url, _ in
                    do {
                        let entries = try await gate.read(url, onStart: { readsStorage.wrappedValue += 1 })
                        await MainActor.run { completedStorage.wrappedValue += 1 }
                        return entries
                    } catch {
                        await MainActor.run { completedStorage.wrappedValue += 1 }
                        throw error
                    }
                },
                validateFile: { url in
                    do {
                        let url = try await gate.validate(url, onStart: { validationsStorage.wrappedValue += 1 })
                        await MainActor.run { completedStorage.wrappedValue += 1 }
                        return url
                    } catch {
                        await MainActor.run { completedStorage.wrappedValue += 1 }
                        throw error
                    }
                }
            )
        }
        VStack(alignment: .leading, spacing: 0) {
            if presented {
                FilePicker(directory: directory,
                           selection: Binding(get: { selectionStorage.wrappedValue }, set: {
                               writesStorage.wrappedValue += 1
                               if allowsSelection { selectionStorage.wrappedValue = $0 }
                           }), allowedExtensions: allowedExtensions, operations: operations,
                           onConfirm: { _ in confirmations += 1; presented = false },
                           onCancel: { cancellations += 1; presented = false })
            } else {
                Text("Picker dismissed.")
                    .focusable()
                    .focused($dismissedFocused)
                    .defaultFocus($dismissedFocused, true)
                    .focusEffectDisabled()
                Spacer()
            }
            Text("S=\(selection?.lastPathComponent ?? "-") W=\(writes) C=\(confirmations) X=\(cancellations)")
            Text("R=\(reads) V=\(validations) D=\(completed) B=\(barrier)")
        }
        .chioTheme(light ? .light : .default)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("b"): barrier += 1
            case .character("o"): presented = true
            default: return .ignored
            }
            return .handled
        }
    }
}

@MainActor
private func withFilePickerScene(
    directory: URL = pickerRoot, gate: FilePickerOperationGate? = nil,
    allowedExtensions: FileExtensionFilter = .all, allowsSelection: Bool = true,
    light: Bool = false, width: Int = 64, height: Int = 20,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: CellSize(width: width, height: height), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let app = FilePickerTestApp(directory: directory, gate: gate, allowedExtensions: allowedExtensions,
                                allowsSelection: allowsSelection, light: light)
    let session = try HostedSceneSession(for: app, sceneID: "file-picker-tests", surface: surface)
    let run = Task { try await session.start() }
    do {
        try await perform(session, surface, recorder)
        session.stop()
        await gate?.shutdown()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        await gate?.shutdown()
        _ = await run.result
        throw error
    }
}

@MainActor
private func pickerBarrier(_ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    let previous = recorder.latest?.sequence
    let next = (recorder.latest?.pickerBarrierValue ?? 0) + 1
    session.send(.key(.character("b"), modifiers: .ctrl))
    return try await recorder.wait(after: previous, description: "picker input barrier \(next)") {
        $0.pickerContains("B=\(next)")
    }
}

@MainActor
private func focusPickerButton(_ label: String, _ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws {
    for _ in 0..<12 {
        if recorder.latest?.pickerFocusedButton(label) == true { return }
        session.send(.key(.tab))
        _ = try await pickerBarrier(session, recorder)
    }
    try #require(recorder.latest?.pickerFocusedButton(label) == true, "Native Tab did not reach \(label)")
}

private extension SemanticHostFrame {
    func pickerContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }

    func pickerHasQuery(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(value) }
    }

    var pickerHasDismissedFocus: Bool {
        guard pickerContains("Picker dismissed."), let focusedIdentity else { return false }
        return semantics.focusRegions.contains { $0.identity == focusedIdentity }
    }

    var pickerHasResultsFocus: Bool {
        guard let focusedIdentity, semantics.focusRegions.contains(where: { $0.identity == focusedIdentity }) else { return false }
        return !semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && ($0.role == .textField || $0.role == .button)
        }
    }

    func pickerFocusedButton(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .button && $0.label == label }
    }

    func pickerButtonEnabled(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .button && $0.label == label && $0.isEnabled }
    }

    var pickerBarrierValue: Int? {
        guard let row = raster.lines.first(where: { $0.contains(" B=") }),
              let value = row.components(separatedBy: " B=").last else { return nil }
        return Int(value.trimmingCharacters(in: .whitespaces))
    }
}
