@testable import ChioDashboard
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct CreateAgentTests {
    @Test("Opening has no premature errors; leaving Name reveals its current error")
    func initialAndBlurValidation() async throws {
        try await withCreationScene { session, _, recorder in
            let initial = try await openForm(session, recorder)
            #expect(!initial.contains("Enter an agent name."))
            #expect(!initial.contains("Enter a test suite."))
            #expect(initial.hasControl(.toggle, label: "Start immediately", value: .boolean(true)))
            let roleOptions = initial.semantics.accessibilityNodes.first {
                $0.role == .picker && $0.label == "Role"
            }?.control?.selection?.options.map(\.label)
            #expect(roleOptions == ["Build", "Review", "Test", "Docs"])
            session.send(.key(.tab))
            let exited = try await recorder.wait(after: initial.sequence, description: "native Tab leaves Name for Role") {
                $0.focuses(.picker, label: "Role") && $0.contains("Enter an agent name.")
            }
            #expect(exited.focusedIdentity != initial.focusedIdentity)
        }
    }

    @Test("Failed submit focuses the first invalid visible field, then the remaining conditional field")
    func firstInvalidFocusAndNarrowErrorVisibility() async throws {
        try await withCreationScene(size: .init(width: 36, height: 18)) { session, _, recorder in
            _ = try await openForm(session, recorder)
            _ = try await chooseTestRole(session, recorder)
            session.send(.key(.character("s"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "failed submit reveals and focuses Name at narrow size") {
                $0.focuses(.textField, label: "Agent name") && $0.contains("Enter an agent name.")
            }
            session.sendInput(Array("Verifier".utf8))
            _ = try await recorder.wait(description: "Name corrected before retry") {
                $0.hasControl(.textField, label: "Agent name", value: .text("Verifier"))
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let suite = try await recorder.wait(description: "failed retry reveals Test suite error and native focus") {
                $0.focuses(.textField, label: "Test suite") && $0.contains("Enter a test suite.")
            }
            #expect(!suite.contains("Enter an agent name."))
            #expect(suite.raster.size == CellSize(width: 36, height: 18))
        }
    }

    @Test("Native conditional Tab navigation retains suite values and toggle activation")
    func conditionalTraversalAndToggle() async throws {
        try await withCreationScene { session, _, recorder in
            _ = try await openForm(session, recorder)
            session.sendInput(Array("Verifier".utf8))
            _ = try await recorder.wait(description: "entered Name") {
                $0.hasControl(.textField, label: "Agent name", value: .text("Verifier"))
            }
            let test = try await chooseTestRole(session, recorder)
            #expect(!test.contains("Enter a test suite."))
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab includes newly inserted suite") {
                $0.focuses(.textField, label: "Test suite")
            }
            session.sendInput(Array("Smoke".utf8))
            _ = try await recorder.wait(description: "suite entered") {
                $0.hasControl(.textField, label: "Test suite", value: .text("Smoke"))
            }
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "Shift-Tab returns from suite to picker") {
                $0.focuses(.picker, label: "Role")
            }
            session.send(.key(.arrowLeft))
            _ = try await recorder.wait(description: "Review removes conditional suite") {
                $0.selectedRole == "Review" && !$0.hasControl(.textField, label: "Test suite")
            }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab skips hidden suite and reaches toggle") {
                $0.focuses(.toggle, label: "Start immediately")
            }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "Space activates native toggle") {
                $0.hasControl(.toggle, label: "Start immediately", value: .boolean(false))
            }
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "Shift-Tab skips hidden suite") {
                $0.focuses(.picker, label: "Role")
            }
            session.send(.key(.arrowRight))
            _ = try await recorder.wait(description: "Test restores retained suite") {
                $0.selectedRole == "Test" && $0.hasControl(.textField, label: "Test suite", value: .text("Smoke"))
            }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "restored suite participates in native Tab") {
                $0.focuses(.textField, label: "Test suite")
            }
        }
    }

    @Test("Theme and resize preserve draft, role, toggle, and native editing focus")
    func themeAndResizePreservation() async throws {
        try await withCreationScene { session, surface, recorder in
            _ = try await openForm(session, recorder)
            session.sendInput(Array("Verifier".utf8))
            _ = try await recorder.wait(description: "entered Name before choosing role") {
                $0.hasControl(.textField, label: "Agent name", value: .text("Verifier"))
            }
            _ = try await chooseTestRole(session, recorder)
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "suite focus before editing") {
                $0.focuses(.textField, label: "Test suite")
            }
            session.sendInput(Array("Smoke".utf8))
            let before = try await recorder.wait(description: "draft ready for theme change") {
                $0.hasControl(.textField, label: "Test suite", value: .text("Smoke"))
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: before.sequence, description: "theme visibly changes") {
                $0.raster.cells != before.raster.cells && $0.focuses(.textField, label: "Test suite")
            }
            #expect(themed.focusedIdentity == before.focusedIdentity)
            #expect(themed.hasControl(.textField, label: "Agent name", value: .text("Verifier")))
            #expect(themed.selectedRole == "Test")
            #expect(themed.hasControl(.toggle, label: "Start immediately", value: .boolean(true)))
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: themed.sequence, description: "narrow resize preserves suite editing") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.focuses(.textField, label: "Test suite")
            }
            #expect(resized.focusedIdentity == themed.focusedIdentity)
            #expect(resized.hasControl(.textField, label: "Agent name", value: .text("Verifier")))
            #expect(resized.hasControl(.textField, label: "Test suite", value: .text("Smoke")))
            #expect(resized.selectedRole == "Test")
            session.sendInput(Array(" tests".utf8))
            _ = try await recorder.wait(description: "native editor continues after theme and resize") {
                $0.hasControl(.textField, label: "Test suite", value: .text("Smoke tests"))
            }
        }
    }

    @Test("Creation clears search, adds one agent, and selects its visible row")
    func successfulCreationClearsQueryAndSelectsAgent() async throws {
        try await withCreationScene { session, _, recorder in
            _ = try await filterBuild(session, recorder)
            _ = try await openForm(session, recorder)
            session.sendInput(Array("Release".utf8))
            _ = try await recorder.wait(description: "valid creation name") {
                $0.hasControl(.textField, label: "Agent name", value: .text("Release"))
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let created = try await recorder.wait(description: "one new agent is selected after creation") {
                $0.isDashboard && $0.contains("5 of 5 items") && $0.hasSelectedRow("Release")
            }
            #expect(created.hasControl(.textField, value: .text("")))
            #expect(created.contains("Opened Release"))
            #expect(created.contains("0%"))
        }
    }

    @Test("Duplicate Return attempts create exactly one agent")
    func duplicateReturnCreatesOnce() async throws {
        try await withCreationScene { session, _, recorder in
            _ = try await openForm(session, recorder)
            session.sendInput(Array("Release".utf8))
            _ = try await recorder.wait(description: "valid name before duplicate submission") {
                $0.hasControl(.textField, label: "Agent name", value: .text("Release"))
            }
            session.sendInput(Array("\r\r".utf8))
            let created = try await recorder.wait(description: "duplicate Return returns to dashboard") {
                $0.isDashboard && $0.contains("5 of 5 items") && $0.hasSelectedRow("Release")
            }
            #expect(!created.contains("6 of 6 items"))
        }
    }

    @Test("Escape cancels and restores dashboard query, selected row, and exact native focus")
    func cancellationRestoresDashboard() async throws {
        try await withCreationScene { session, _, recorder in
            let before = try await filterBuild(session, recorder)
            _ = try await openForm(session, recorder)
            session.sendInput(Array("Discard me".utf8))
            _ = try await recorder.wait(description: "draft entered before cancel") {
                $0.hasControl(.textField, label: "Agent name", value: .text("Discard me"))
            }
            session.send(.key(.escape))
            let cancelled = try await recorder.wait(description: "dashboard restored after cancellation") {
                $0.isDashboard && $0.hasControl(.textField, value: .text("build")) && $0.contains("1 of 4 items")
            }
            #expect(cancelled.focusedIdentity == before.focusedIdentity)
            #expect(cancelled.hasSelectedRow("Build Agent"))
            #expect(!cancelled.contains("Discard me"))
        }
    }

    @Test("Raw n plus q carries type-ahead into Name without quitting")
    func batchedOpenAndPrintable() async throws {
        try await withCreationScene { session, _, recorder in
            _ = try await waitForDashboard(recorder)
            session.sendInput(Array("nq".utf8))
            _ = try await recorder.wait(description: "batched n-q edits Name and keeps session alive") {
                $0.focuses(.textField, label: "Agent name") && $0.hasControl(.textField, label: "Agent name", value: .text("q"))
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "session remains usable after batched n-q") { $0.isDashboard }
        }
    }

    @Test("Raw n plus Tab advances from the form's default Name focus to Role")
    func batchedOpenAndTab() async throws {
        try await withCreationScene { session, _, recorder in
            _ = try await waitForDashboard(recorder)
            session.sendInput(Array("n\t".utf8))
            let tabbed = try await recorder.wait(description: "batched n-Tab advances to native Role picker") {
                $0.focuses(.picker, label: "Role")
            }
            #expect(tabbed.hasControl(.textField, label: "Agent name", value: .text("")))
        }
    }

    @Test("Opening, typing, and submitting in one read creates exactly one agent",
          arguments: ["nRelease\r\r", "nRelease\u{13}\u{13}"])
    func batchedOpenAndSubmit(_ input: String) async throws {
        try await withCreationScene { session, _, recorder in
            let before = try await waitForDashboard(recorder)
            session.sendInput(Array(input.utf8))
            let created = try await recorder.wait(after: before.sequence, description: "batched creation submits once") {
                $0.isDashboard && $0.contains("5 of 5 items") && $0.hasSelectedRow("Release")
            }
            #expect(!created.contains("6 of 6 items"))
            #expect(created.contains("q quit"))
        }
    }

    @Test("Invalid submission in the opening read reveals errors when the form arrives")
    func batchedOpenAndInvalidSubmit() async throws {
        try await withCreationScene { session, _, recorder in
            _ = try await waitForDashboard(recorder)
            session.sendInput(Array("n\r".utf8))
            _ = try await recorder.wait(description: "opening submission validates Name") {
                $0.focuses(.textField, label: "Agent name") && $0.contains("Enter an agent name.")
            }
        }
    }
}

private struct CreationTestApp {
    nonisolated init() {}
}

extension CreationTestApp: App {
    var body: some Scene {
        WindowGroup(id: "creation-tests") { DashboardView(animates: false, paused: true) }
            .exitOnKeys([])
    }
}

@MainActor
private func withCreationScene(
    size: CellSize = .init(width: 100, height: 30),
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: size, appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: CreationTestApp(), sceneID: "creation-tests", surface: surface)
    let run = Task { try await session.start() }
    defer { session.stop() }
    do {
        try await perform(session, surface, recorder)
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        _ = await run.result
        throw error
    }
}

@MainActor
private func waitForDashboard(_ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    try await recorder.wait(description: "dashboard has native results focus") {
        $0.isDashboard && $0.focusedIdentity != nil && !$0.focuses(.textField)
    }
}

@MainActor
private func openForm(_ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    _ = try await waitForDashboard(recorder)
    session.send(.key(.character("n")))
    return try await recorder.wait(description: "form has default native Name focus") {
        $0.contains("/ create agent") && $0.focuses(.textField, label: "Agent name")
    }
}

@MainActor
private func chooseTestRole(_ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    session.send(.key(.tab))
    _ = try await recorder.wait(description: "native Tab focuses Role") { $0.focuses(.picker, label: "Role") }
    session.send(.key(.arrowRight))
    _ = try await recorder.wait(description: "native picker selects Review") { $0.selectedRole == "Review" }
    session.send(.key(.arrowRight))
    return try await recorder.wait(description: "native picker selects Test and inserts required suite") {
        $0.selectedRole == "Test" && $0.hasControl(.textField, label: "Test suite", value: .text(""))
    }
}

@MainActor
private func filterBuild(_ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    _ = try await waitForDashboard(recorder)
    session.sendInput(Array("/build\r".utf8))
    return try await recorder.wait(description: "filtered dashboard retains selected Build and results focus") {
        $0.isDashboard && $0.hasControl(.textField, value: .text("build")) && !$0.focuses(.textField)
            && $0.contains("1 of 4 items") && $0.hasSelectedRow("Build Agent")
    }
}

private extension SemanticHostFrame {
    var isDashboard: Bool { contains("/ agent workspace") && !contains("/ create agent") }

    var selectedRole: String? {
        guard let node = semantics.accessibilityNodes.first(where: { $0.role == .picker && $0.label == "Role" }),
              let value = node.control?.value,
              case .text(let selectedID) = value else { return nil }
        return node.control?.selection?.options.first { $0.id == selectedID }?.label
    }

    func hasControl(_ role: AccessibilityRole, label: String? = nil, value: AccessibilityValue? = nil) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.role == role && (label == nil || $0.label == label) && (value == nil || $0.control?.value == value)
        }
    }

    func focuses(_ role: AccessibilityRole, label: String? = nil) -> Bool {
        guard let focusedIdentity else { return false }
        return semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == role && (label == nil || $0.label == label)
        }
    }

    func contains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }

    func hasSelectedRow(_ name: String) -> Bool {
        raster.lines.contains { $0.contains(name) && $0.contains("›") }
    }
}
