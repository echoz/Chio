@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct FeedbackExampleTests {
    @Test("Confirm, Escape, completion toast and destructive reset retain native focus")
    func workflow() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 76, height: 26), appearance: .fallback,
                                          onFrame: recorder.receive)
        let session = try HostedSceneSession(for: FeedbackTestApp(), sceneID: "feedback-tests", surface: surface)
        let run = Task { try await session.start() }
        do {
            let ready = try await recorder.wait(description: "ready with Publish focused") {
                $0.feedbackFocused("Publish") && $0.feedbackContains("Ready to publish")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            _ = try await recorder.wait(after: ready.sequence, description: "theme changes without losing trigger focus") {
                $0.focusedIdentity == ready.focusedIdentity && $0.raster.cells.flatMap { $0 }.contains {
                    $0.style?.foregroundColor == ChioTheme.light.colors.accent
                }
            }
            session.send(.key(.return))
            let opened = try await recorder.wait(description: "confirmation opens") { $0.feedbackContains("Publish report?") }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            _ = try await recorder.wait(after: opened.sequence, description: "light prompt retains content through narrow resize") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.feedbackContains("Publish report?")
                    && $0.feedbackContains("Cancel") && $0.raster.cells.flatMap { $0 }.contains {
                        $0.style?.foregroundColor == ChioTheme.light.colors.accent
                    }
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "Escape restores trigger") {
                !$0.feedbackContains("Publish report?") && $0.focusedIdentity == ready.focusedIdentity
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "confirmation reopens") { $0.feedbackContains("Publish report?") }
            try await focusAction("Cancel", session: session, recorder: recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "Cancel restores trigger") {
                !$0.feedbackContains("Publish report?") && $0.focusedIdentity == ready.focusedIdentity
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "confirmation ready to publish") { $0.feedbackContains("Publish report?") }
            try await focusAction("Publish", session: session, recorder: recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "native spinner active") {
                $0.feedbackContains("Publishing report") && !$0.feedbackContains("Publish report?")
            }
            let completed = try await recorder.wait(description: "completion toast") {
                $0.feedbackContains("Report published") && $0.feedbackContains("Published · ready to share")
            }
            let expired = try await recorder.wait(after: completed.sequence, description: "toast expires without taking focus") {
                $0.feedbackContains("Report published") && !$0.feedbackContains("Published · ready to share")
            }
            #expect(expired.focusedIdentity == completed.focusedIdentity)
            session.send(.key(.character("d"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "destructive alert") { $0.feedbackContains("Discard report?") }
            try await focusAction("Discard", session: session, recorder: recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "result discarded") {
                $0.feedbackContains("Ready to publish") && !$0.feedbackContains("Discard report?")
            }
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    @Test("Feedback example keeps actions and help visible", arguments: [CellSize(width: 100, height: 30),
          CellSize(width: 50, height: 30), CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        let frame = DefaultRenderer().render(FeedbackExampleView(light: light).environment(\.terminalSize, size),
                                            proposal: .init(width: size.width, height: size.height), frameInstant: .zero)
        let text = frame.rasterSurface.lines.joined(separator: "\n")
        #expect(frame.rasterSurface.size == size)
        #expect(text.contains("Release report"))
        #expect(text.contains("Ready to publish"))
        #expect(text.contains("Publish") && text.contains("Discard"))
        #expect(text.contains("^P publish") && text.contains("^Q quit"))
        #expect(frame.semanticSnapshot.accessibilityNodes.contains { $0.label == "Discard" && !$0.isEnabled })
    }
}

@MainActor
private func focusAction(_ label: String, session: HostedSceneSession, recorder: HostedFrameRecorder) async throws {
    var frame = try await recorder.wait(description: "modal focus") { $0.focusedIdentity != nil }
    for _ in 0..<6 {
        if frame.feedbackFocused(label) { return }
        let previous = frame
        session.send(.key(.tab))
        frame = try await recorder.wait(after: previous.sequence, description: "native Tab advances") {
            $0.focusedIdentity != previous.focusedIdentity
        }
    }
    #expect(frame.feedbackFocused(label))
}

private struct FeedbackTestApp {}

extension FeedbackTestApp: App {
    var body: some Scene {
        WindowGroup(id: "feedback-tests") { FeedbackExampleView() }.exitOnKeys([])
    }
}

private extension SemanticHostFrame {
    func feedbackContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    func feedbackFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.label == label }
    }
}
