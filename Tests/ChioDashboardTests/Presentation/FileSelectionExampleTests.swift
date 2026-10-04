@testable import ChioDashboard
import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct FileSelectionExampleTests {
    @Test("Real folder navigation, confirmation, reopening and cancellation preserve the committed file")
    func workflow() async throws {
        try await withFileSelectionExample { session, _, recorder, directory in
            _ = try await recorder.wait(description: "folder loaded") { $0.fileContains("alpha.txt") && $0.fileResultsFocused }
            try await filterFile("nested", session: session, recorder: recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "nested folder loaded") { $0.fileContains("inside.txt") }
            try await filterFile("inside", session: session, recorder: recorder)
            session.send(.key(.return))
            let confirmed = try await recorder.wait(description: "file confirmed") { $0.fileContains("Selected file") }
            #expect(confirmed.fileContains("inside.txt"))
            #expect(confirmed.semantics.accessibilityNodes.contains {
                $0.label == directory.appendingPathComponent("nested/inside.txt").path
            })
            session.send(.key(.character("o"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "reopened original folder") { $0.fileContains("alpha.txt") && $0.fileResultsFocused }
            try await filterFile("alpha", session: session, recorder: recorder)
            session.send(.key(.character("g"), modifiers: .ctrl))
            let cancelled = try await recorder.wait(description: "cancel keeps previous confirmation") { $0.fileContains("Cancelled") }
            #expect(cancelled.fileContains("inside.txt"))
            #expect(!cancelled.fileContains("Selected file"))
            session.send(.key(.return))
            _ = try await recorder.wait(description: "native reopen button works") { $0.fileContains("alpha.txt") && $0.fileResultsFocused }
        }
    }

    @Test("Filtering, focus and actions survive theme change and compact geometry")
    func compactInteraction() async throws {
        try await withFileSelectionExample { session, surface, recorder, _ in
            _ = try await recorder.wait(description: "folder ready") { $0.fileContains("alpha.txt") && $0.fileResultsFocused }
            try await filterFile("alpha", session: session, recorder: recorder)
            let before = try await recorder.wait(description: "filtered row focused") { $0.fileQuery("alpha") && $0.fileResultsFocused }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: before.sequence, description: "theme preserves query and focus") {
                $0.fileQuery("alpha") && $0.focusedIdentity == before.focusedIdentity && $0.raster.cells != before.raster.cells
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: themed.sequence, description: "compact picker ready") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.fileQuery("alpha") && $0.fileResultsFocused
            }
            #expect(compact.fileContains("alpha.txt"))
            #expect(compact.fileContains("Parent") && compact.fileContains("Choose") && compact.fileContains("Cancel"))
            #expect(compact.fileContains("^Q quit"))
            session.send(.key(.return))
            _ = try await recorder.wait(description: "compact confirmation") { $0.fileContains("Selected file") && $0.fileContains("alpha.txt") }
        }
    }
}

@MainActor
private func filterFile(_ query: String, session: HostedSceneSession, recorder: HostedFrameRecorder) async throws {
    session.send(.key(.character("/")))
    _ = try await recorder.wait(description: "search editor focused") { $0.fileEditorFocused }
    session.sendInput(Array(query.utf8))
    _ = try await recorder.wait(description: "file filter committed") { $0.fileQuery(query) }
    session.send(.key(.return))
    _ = try await recorder.wait(description: "file results focused") { $0.fileQuery(query) && $0.fileResultsFocused }
}

private struct FileSelectionTestApp {
    let directory: URL

    nonisolated init() { directory = URL(fileURLWithPath: "/", isDirectory: true) }
    nonisolated init(directory: URL) { self.directory = directory }
}

extension FileSelectionTestApp: App {
    var body: some Scene {
        WindowGroup(id: "file-selection-tests") { FileSelectionExampleView(directory: directory) }.exitOnKeys([])
    }
}

@MainActor
private func withFileSelectionExample(
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder, URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chio-files-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("alpha".utf8).write(to: directory.appendingPathComponent("alpha.txt"))
    try Data("inside".utf8).write(to: directory.appendingPathComponent("nested/inside.txt"))
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                      onFrame: recorder.receive)
    let session = try HostedSceneSession(for: FileSelectionTestApp(directory: directory), sceneID: "file-selection-tests", surface: surface)
    let run = Task { try await session.start() }
    do {
        try await perform(session, surface, recorder, directory)
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        _ = await run.result
        throw error
    }
}

private extension SemanticHostFrame {
    func fileContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    func fileQuery(_ query: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(query) }
    }
    var fileEditorFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .textField }
    }
    var fileResultsFocused: Bool {
        !fileEditorFocused && raster.lines.contains { $0.contains("▌") }
    }
}
