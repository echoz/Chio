@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct GroupedFormExampleTests {
    @Test("Grouped settings retain actions, native values and hints across themes and sizes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        for scheduled in [false, true] {
            let rendered = DefaultRenderer().render(
                GroupedFormExampleView(light: light, initialDraft: .init(automaticRuns: scheduled))
                    .environment(\.terminalSize, size),
                proposal: .init(width: size.width, height: size.height), frameInstant: .zero
            )
            let text = rendered.rasterSurface.lines.joined(separator: "\n")
            #expect(rendered.rasterSurface.size == size)
            #expect(text.contains("/ grouped forms"))
            #expect(text.contains("Workspace"))
            #expect(text.contains("Save") && text.contains("Cancel"))
            #expect(text.contains("^S save") && text.contains("^X cancel") && text.contains("^Q quit"))
            #expect(text.contains("Saved: Chio · manual"))
            #expect(!text.contains("Error:"))
            let nodes = rendered.semanticSnapshot.accessibilityNodes
            #expect(nodes.contains { $0.role == .textField && $0.label == "Workspace name" && $0.control?.value == .text("Chio") })
            #expect(nodes.contains { $0.role == .toggle && $0.label == "Automatic runs" && $0.control?.value == .boolean(scheduled) })
            #expect(nodes.contains { $0.role == .textField && $0.label == "Interval" && $0.control?.value == .text("15") } == scheduled)
            #expect(nodes.contains { $0.role == .textField && $0.label == "Timeout" && $0.control?.value == .text("5") } == scheduled)
            let theme: ChioTheme = light ? .light : .default
            #expect(rendered.rasterSurface.cells.flatMap { $0 }.contains {
                $0.character == "W" && $0.style?.foregroundColor == theme.colors.heading
            })
        }
    }

    @Test("Batched native editing saves current values and Cancel restores the latest accepted snapshot")
    func saveRejectAndCancel() async throws {
        try await withGroupedForm { session, _, recorder in
            let initial = try await recorder.wait(description: "default Name focus and saved baseline") {
                $0.formFocused("Workspace name") && $0.formValue("Workspace name", "Chio")
                    && $0.formContains("Saved: Chio · manual")
            }
            session.send([.key(.end), .key(.character("A")), .key(.character("B")),
                          .key(.character("s"), modifiers: .ctrl)])
            let saved = try await recorder.wait(after: initial.sequence, description: "Save sees both edits from the same input batch") {
                $0.formValue("Workspace name", "ChioAB") && $0.formContains("Saved: ChioAB · manual")
                    && $0.formContains("Saved locally")
            }
            session.send([.key(.character("C")), .key(.return)])
            let submitted = try await recorder.wait(after: saved.sequence, description: "TextField Return saves the newer snapshot") {
                $0.formValue("Workspace name", "ChioABC") && $0.formContains("Saved: ChioABC · manual")
            }
            session.send(formReplacement(" ") + [.key(.character("s"), modifiers: .ctrl)])
            let rejected = try await recorder.wait(after: submitted.sequence, description: "rejected Save preserves the accepted snapshot") {
                $0.formFocused("Workspace name") && $0.formValue("Workspace name", " ")
                    && $0.formContains("Enter a workspace name.") && $0.formContains("Not saved")
                    && $0.formContains("Saved: ChioABC · manual")
            }
            try await focusForm("Cancel", session: session, recorder: recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(after: rejected.sequence, description: "native Cancel restores latest Save and resets visibility") {
                $0.formFocused("Workspace name") && $0.formValue("Workspace name", "ChioABC")
                    && $0.formContains("Cancelled") && !$0.formContains("Error:")
                    && $0.formContains("Saved: ChioABC · manual")
            }
        }
    }

    @Test("Native toggle activation retains hidden raw input and validates only visible settings")
    func conditionalValues() async throws {
        let initialDraft = RunSettingsDraft(name: "Local", automaticRuns: true,
                                            intervalMinutes: "17", timeoutMinutes: "unfinished")
        try await withGroupedForm(initialDraft: initialDraft) { session, _, recorder in
            _ = try await recorder.wait(description: "scheduled draft starts without changing the saved baseline") {
                $0.formFocused("Workspace name") && $0.formValue("Interval", "17")
                    && $0.formValue("Timeout", "unfinished") && $0.formContains("Saved: Chio · manual")
            }
            try await focusForm("Automatic runs", session: session, recorder: recorder)
            session.send(.key(.return))
            let hidden = try await recorder.wait(description: "Return toggles the native control without submitting") {
                $0.formFocused("Automatic runs") && $0.formAutomatic(false)
                    && !$0.formHasField("Interval") && !$0.formHasField("Timeout")
                    && $0.formContains("Saved: Chio · manual")
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let manual = try await recorder.wait(after: hidden.sequence, description: "hidden invalid minutes do not reject manual Save") {
                $0.formAutomatic(false) && $0.formContains("Saved: Local · manual")
                    && $0.formContains("Saved locally") && !$0.formContains("Error:")
            }
            session.send(.key(.space))
            _ = try await recorder.wait(after: manual.sequence, description: "Space restores the unmodified hidden strings") {
                $0.formAutomatic(true) && $0.formValue("Interval", "17")
                    && $0.formValue("Timeout", "unfinished") && !$0.formContains("Error:")
            }
            try await focusForm("Timeout", session: session, recorder: recorder)
            session.send(formReplacement("3") + [.key(.character("s"), modifiers: .ctrl)])
            let scheduled = try await recorder.wait(description: "valid related values are saved atomically") {
                $0.formAutomatic(true) && $0.formValue("Interval", "17") && $0.formValue("Timeout", "3")
                    && $0.formContains("Saved: Local · every 17m, timeout 3m") && $0.formContains("Saved locally")
            }
            session.send(formReplacement("bad"))
            _ = try await recorder.wait(after: scheduled.sequence, description: "later invalid edit remains an unsaved draft") {
                $0.formValue("Timeout", "bad") && $0.formContains("Unsaved changes")
            }
            session.send(.key(.character("x"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "Cancel restores the last scheduled snapshot and Name focus") {
                $0.formFocused("Workspace name") && $0.formValue("Workspace name", "Local")
                    && $0.formAutomatic(true) && $0.formValue("Interval", "17") && $0.formValue("Timeout", "3")
                    && $0.formContains("Cancelled") && !$0.formContains("Error:")
            }
        }
    }

    @Test("Cancel clears hidden-field visits while later native blur still validates")
    func cancelResetsHiddenFieldValidation() async throws {
        let initialDraft = RunSettingsDraft(name: "Local", automaticRuns: true,
                                            intervalMinutes: "17", timeoutMinutes: "unfinished")
        try await withGroupedForm(initialDraft: initialDraft) { session, _, recorder in
            _ = try await recorder.wait(description: "scheduled draft has no eager error") {
                $0.formFocused("Workspace name") && $0.formValue("Timeout", "unfinished")
                    && !$0.formContains("Error:")
            }
            try await focusForm("Automatic runs", session: session, recorder: recorder)
            session.send(.key(.return))
            let hidden = try await recorder.wait(description: "native toggle hides unfinished minutes") {
                $0.formFocused("Automatic runs") && $0.formAutomatic(false)
                    && !$0.formHasField("Timeout")
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let saved = try await recorder.wait(after: hidden.sequence, description: "manual Save accepts the retained hidden draft") {
                $0.formAutomatic(false) && $0.formContains("Saved: Local · manual")
                    && $0.formContains("Saved locally")
            }
            session.send(.key(.return))
            _ = try await recorder.wait(after: saved.sequence, description: "native toggle restores unfinished Timeout") {
                $0.formFocused("Automatic runs") && $0.formAutomatic(true)
                    && $0.formValue("Interval", "17") && $0.formValue("Timeout", "unfinished")
            }
            try await focusForm("Timeout", session: session, recorder: recorder)
            let focused = try await recorder.wait(description: "unfinished Timeout is focused before Cancel") {
                $0.formFocused("Timeout") && $0.formValue("Timeout", "unfinished")
            }
            session.send(.key(.character("x"), modifiers: .ctrl))
            let cancelled = try await recorder.wait(after: focused.sequence, description: "Cancel restores manual Save and Name focus") {
                $0.formFocused("Workspace name") && $0.formValue("Workspace name", "Local")
                    && $0.formAutomatic(false) && !$0.formHasField("Timeout")
                    && $0.formContains("Saved: Local · manual") && $0.formContains("Cancelled")
                    && !$0.formContains("Error:")
            }
            try await focusForm("Automatic runs", session: session, recorder: recorder)
            session.send(.key(.return))
            let reopened = try await recorder.wait(after: cancelled.sequence, description: "reopening after Cancel retains raw minutes") {
                $0.formFocused("Automatic runs") && $0.formAutomatic(true)
                    && $0.formValue("Interval", "17") && $0.formValue("Timeout", "unfinished")
            }
            #expect(!reopened.formContains("Error:"))
            #expect(!reopened.semantics.accessibilityNodes.contains {
                $0.label?.hasPrefix("Error:") == true
            })
            try await focusForm("Timeout", session: session, recorder: recorder)
            let revisited = try await recorder.wait(description: "Timeout is revisited without another submission") {
                $0.formFocused("Timeout") && $0.formValue("Timeout", "unfinished")
            }
            #expect(!revisited.formContains("Error:"))
            #expect(!revisited.semantics.accessibilityNodes.contains {
                $0.label?.hasPrefix("Error:") == true
            })
            try await focusForm("Save", session: session, recorder: recorder)
            let blurred = try await recorder.wait(after: revisited.sequence, description: "later native blur adds the retained Timeout's inline error") {
                $0.formFocused("Save") && $0.formValue("Timeout", "unfinished")
                    && $0.semantics.accessibilityNodes.contains {
                        $0.label == "Error: Use whole minutes from 1 to 60."
                    }
                    && $0.formContains("Saved: Local · manual")
            }
            // Save is outside the viewport; submission must reveal the complete invalid field.
            session.send(.key(.return))
            _ = try await recorder.wait(after: blurred.sequence, description: "submission focuses Timeout and reveals its inline error") {
                $0.formFocused("Timeout") && $0.formContains("Use whole minutes from 1 to 60.")
                    && $0.formContains("Not saved") && $0.formContains("Saved: Local · manual")
            }
        }
    }

    @Test("Ordered errors reveal native fields and retain their draft and focus through theme and compact resize")
    func validationThemeAndResize() async throws {
        let initialDraft = RunSettingsDraft(name: "", automaticRuns: true,
                                            intervalMinutes: "bad", timeoutMinutes: "bad")
        try await withGroupedForm(initialDraft: initialDraft) { session, surface, recorder in
            _ = try await recorder.wait(description: "invalid initial draft has native Name focus without eager errors") {
                $0.formFocused("Workspace name") && $0.formValue("Workspace name", "") && !$0.formContains("Error:")
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "first invalid Name is focused with its visible error") {
                $0.formFocused("Workspace name") && $0.formContains("Enter a workspace name.")
            }
            session.send(formReplacement("Atlas") + [.key(.character("s"), modifiers: .ctrl)])
            _ = try await recorder.wait(description: "correcting Name reveals the invalid Interval") {
                $0.formFocused("Interval") && $0.formValue("Workspace name", "Atlas")
                    && $0.formContains("Use whole minutes")
            }
            session.send(formReplacement("5") + [.key(.character("s"), modifiers: .ctrl)])
            _ = try await recorder.wait(description: "correcting Interval reveals the invalid Timeout") {
                $0.formFocused("Timeout") && $0.formValue("Interval", "5")
                    && $0.formValue("Timeout", "bad") && $0.formContains("Use whole minutes")
            }
            session.send(formReplacement("5") + [.key(.character("s"), modifiers: .ctrl)])
            let related = try await recorder.wait(description: "equal minutes show the cross-field error without changing saved settings") {
                $0.formFocused("Timeout") && $0.formValue("Timeout", "5")
                    && $0.formContains("Timeout must be shorter") && $0.formContains("Saved: Chio · manual")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: related.sequence, description: "theme retains values, error and native Timeout identity") {
                $0.formFocused("Timeout") && $0.formValue("Interval", "5") && $0.formValue("Timeout", "5")
                    && $0.formContains("Timeout must be shorter") && $0.raster.cells != related.raster.cells
            }
            #expect(themed.focusedIdentity == related.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: themed.sequence, description: "compact focus reveals the wrapping error and retains actions") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.formFocused("Timeout")
                    && $0.formValue("Workspace name", "Atlas") && $0.formValue("Interval", "5")
                    && $0.formValue("Timeout", "5") && $0.formContains("Timeout must")
                    && $0.formContains("shorter") && $0.formContains("Save") && $0.formContains("Cancel")
                    && $0.formContains("^Q quit")
            }
            #expect(compact.focusedIdentity == related.focusedIdentity)
            try await focusForm("Interval", session: session, recorder: recorder)
            session.send(formReplacement("6"))
            _ = try await recorder.wait(description: "the other related field is edited natively") {
                $0.formFocused("Interval") && $0.formValue("Interval", "6") && $0.formValue("Timeout", "5")
            }
            try await focusForm("Save", session: session, recorder: recorder)
            session.send(.key(.return))
            let corrected = try await recorder.wait(description: "fixing the other side accepts the unchanged Timeout") {
                $0.formValue("Interval", "6") && $0.formValue("Timeout", "5")
                    && $0.formContains("Saved locally") && $0.formContains("Saved: Atlas · every 6m")
            }
            try await focusForm("Timeout", session: session, recorder: recorder)
            session.send(formReplacement("invalid") + [.key(.character("s"), modifiers: .ctrl)])
            _ = try await recorder.wait(after: corrected.sequence, description: "a later rejected edit leaves the newly saved snapshot intact") {
                $0.formFocused("Timeout") && $0.formValue("Timeout", "invalid")
                    && $0.formContains("Not saved") && $0.formContains("Saved: Atlas · every 6m")
            }
            session.send(.key(.character("x"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "compact Cancel restores all saved fields and clears errors") {
                $0.formFocused("Workspace name") && $0.formValue("Workspace name", "Atlas")
                    && $0.formAutomatic(true) && $0.formValue("Interval", "6") && $0.formValue("Timeout", "5")
                    && $0.formContains("Cancelled") && !$0.formContains("Error:")
            }
        }
    }
}

private struct GroupedFormTestApp {
    let initialDraft: RunSettingsDraft
    nonisolated init() { initialDraft = .init() }
    nonisolated init(initialDraft: RunSettingsDraft) { self.initialDraft = initialDraft }
}

extension GroupedFormTestApp: App {
    var body: some Scene {
        WindowGroup(id: "grouped-form-tests") { GroupedFormExampleView(initialDraft: initialDraft) }.exitOnKeys([])
    }
}

@MainActor
private func withGroupedForm(
    initialDraft: RunSettingsDraft = .init(),
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: GroupedFormTestApp(initialDraft: initialDraft),
                                        sceneID: "grouped-form-tests", surface: surface)
    let run = Task { try await session.start() }
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

private func formReplacement(_ text: String) -> [InputEvent] {
    [.key(.home), .key(.end, modifiers: .shift), .paste(PasteEvent(content: text))]
}

@MainActor
private func focusForm(_ label: String, session: HostedSceneSession, recorder: HostedFrameRecorder) async throws {
    var current = try await recorder.wait(description: "current grouped form focus") { $0.focusedIdentity != nil }
    for _ in 0..<10 {
        if current.formFocused(label) { return }
        let previous = current.focusedIdentity
        session.send(.key(.tab))
        current = try await recorder.wait(after: current.sequence, description: "Tab advances native grouped form focus") {
            $0.focusedIdentity != nil && $0.focusedIdentity != previous
        }
    }
    throw GroupedFormFocusError(label: label)
}

private struct GroupedFormFocusError { let label: String }

extension GroupedFormFocusError: Error {}

private extension SemanticHostFrame {
    func formContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    func formFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.label == label }
    }
    func formHasField(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.label == label }
    }
    func formValue(_ label: String, _ value: String) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.role == .textField && $0.label == label && $0.control?.value == .text(value)
        }
    }
    func formAutomatic(_ enabled: Bool) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.role == .toggle && $0.label == "Automatic runs" && $0.control?.value == .boolean(enabled)
        }
    }
}
