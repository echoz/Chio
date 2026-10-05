@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct TimerExampleTests {
    @Test("Time studio keeps both clocks, native actions and hints across themes and sizes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 76, height: 30),
                      CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        let rendered = DefaultRenderer().render(
            TimerExampleView(light: light, now: { .zero }).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(rendered.rasterSurface.size == size)
        #expect(text.contains("/ time studio"))
        #expect(text.contains("Stopwatch") && text.contains("Countdown"))
        #expect(text.contains("0:00") && text.contains("0:20"))
        #expect(text.contains("s stopwatch") && text.contains("c countdown"))
        #expect(text.contains("r reset both") && text.contains("^T theme") && text.contains("^Q quit"))
        let nodes = rendered.semanticSnapshot.accessibilityNodes
        for label in ["Start stopwatch", "Reset stopwatch", "Start countdown", "Reset countdown"] {
            #expect(nodes.contains { $0.role == .button && $0.label == label && $0.isEnabled })
        }
        #expect(nodes.contains { $0.label == "Elapsed time: 0 seconds" })
        #expect(nodes.contains { $0.label == "Remaining time: 20 seconds" })
        let theme: ChioTheme = light ? .light : .default
        #expect(rendered.rasterSurface.cells.flatMap { $0 }.contains {
            $0.character == "0" && $0.style?.foregroundColor == theme.colors.accent
        })
    }

    @Test("Native stopwatch actions sample dispatch time, retain pauses and survive theme and compact resize")
    func stopwatchWorkflow() async throws {
        let clock = TimerTestClock()
        try await withTimer(now: { clock.instant }) { session, surface, recorder in
            let initial = try await recorder.wait(description: "native Start stopwatch is ready") {
                $0.timerFocused("Start stopwatch") && $0.timerElapsed("0 seconds") && $0.timerRemaining("20 seconds")
            }
            session.send(.key(.return))
            let started = try await recorder.wait(after: initial.sequence, description: "Return starts the stopwatch") {
                $0.timerFocused("Pause stopwatch") && $0.timerButton("Pause stopwatch")
            }
            // Do not refresh first: Pause must sample the newly advanced clock at input dispatch.
            clock.advance(by: .milliseconds(2_900))
            session.send(.key(.return))
            let paused = try await recorder.wait(after: started.sequence, description: "Pause uses current time rather than the preceding zero frame") {
                $0.timerFocused("Resume stopwatch") && $0.timerElapsed("2 seconds") && $0.timerRemaining("20 seconds")
            }
            clock.advance(by: .seconds(100))
            session.requestSurfaceRefresh()
            let held = try await recorder.wait(after: paused.sequence, description: "a long paused gap contributes no elapsed time") {
                $0.timerElapsed("2 seconds") && $0.timerFocused("Resume stopwatch")
            }
            session.send(.key(.return))
            let resumed = try await recorder.wait(after: held.sequence, description: "Return resumes the retained stopwatch interval") {
                $0.timerFocused("Pause stopwatch") && $0.timerElapsed("2 seconds")
            }
            clock.advance(by: .milliseconds(200))
            session.requestSurfaceRefresh()
            let advanced = try await recorder.wait(after: resumed.sequence, description: "the second interval joins retained fractional elapsed time") {
                $0.timerElapsed("3 seconds") && $0.timerRemaining("20 seconds")
            }
            // A trailing native Tab is a processing barrier for the four shortcut transitions.
            session.sendInput(Array("ssss\t".utf8))
            let batched = try await recorder.wait(after: advanced.sequence, description: "four rapid toggles retain running state and native Tab reaches Reset") {
                $0.timerFocused("Reset stopwatch") && $0.timerButton("Pause stopwatch")
                    && $0.timerElapsed("3 seconds") && $0.timerRemaining("20 seconds")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: batched.sequence, description: "theme changes retain both clock values and native button focus") {
                $0.timerFocused("Reset stopwatch") && $0.focusedIdentity == batched.focusedIdentity
                    && $0.timerElapsed("3 seconds") && $0.timerRemaining("20 seconds")
                    && $0.raster.cells != batched.raster.cells
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: themed.sequence, description: "compact layout retains the running clock and focused Reset action") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.timerFocused("Reset stopwatch")
                    && $0.timerElapsed("3 seconds") && $0.timerRemaining("20 seconds") && $0.timerContains("^Q quit")
            }
            session.send(.key(.return))
            _ = try await recorder.wait(after: compact.sequence, description: "native Reset clears only the stopwatch and leaves focus on its action") {
                $0.timerFocused("Reset stopwatch") && $0.timerButton("Start stopwatch")
                    && $0.timerElapsed("0 seconds") && $0.timerRemaining("20 seconds")
            }
        }
    }

    @Test("Countdown pause, completion and native reset leave the independent stopwatch running")
    func countdownWorkflow() async throws {
        let clock = TimerTestClock()
        try await withTimer(now: { clock.instant }) { session, _, recorder in
            let initial = try await recorder.wait(description: "both clocks initially paused") {
                $0.timerFocused("Start stopwatch") && $0.timerButton("Start countdown")
            }
            session.sendInput(Array("sc\t".utf8))
            let started = try await recorder.wait(after: initial.sequence, description: "batched shortcuts start both clocks before native Tab") {
                $0.timerFocused("Reset stopwatch") && $0.timerButton("Pause stopwatch") && $0.timerButton("Pause countdown")
            }
            clock.advance(by: .seconds(3))
            session.requestSurfaceRefresh()
            let advanced = try await recorder.wait(after: started.sequence, description: "explicit time advances both independent clocks") {
                $0.timerElapsed("3 seconds") && $0.timerRemaining("17 seconds")
            }
            try await focusTimer("Pause countdown", session: session, recorder: recorder)
            clock.advance(by: .milliseconds(1_250))
            session.send(.key(.return))
            let paused = try await recorder.wait(after: advanced.sequence, description: "native countdown Pause samples current dispatch time") {
                $0.timerFocused("Resume countdown") && $0.timerElapsed("4 seconds") && $0.timerRemaining("16 seconds")
            }
            clock.advance(by: .seconds(7))
            session.requestSurfaceRefresh()
            let held = try await recorder.wait(after: paused.sequence, description: "only the stopwatch advances through countdown's paused interval") {
                $0.timerElapsed("11 seconds") && $0.timerRemaining("16 seconds") && $0.timerButton("Resume countdown")
            }
            session.send(.key(.character("c")))
            let resumed = try await recorder.wait(after: held.sequence, description: "countdown shortcut resumes without resetting its interval") {
                $0.timerButton("Pause countdown") && $0.timerRemaining("16 seconds")
            }
            clock.advance(by: .milliseconds(15_750))
            session.requestSurfaceRefresh()
            let complete = try await recorder.wait(after: resumed.sequence, description: "expiry pauses countdown and disables its start-resume action") {
                $0.timerElapsed("27 seconds") && $0.timerRemaining("0 seconds") && $0.timerContains("Complete")
                    && $0.timerButton("Resume countdown", enabled: false) && $0.timerButton("Pause stopwatch")
            }
            try await focusTimer("Reset countdown", session: session, recorder: recorder)
            session.sendInput(Array("c\t".utf8))
            let refused = try await recorder.wait(after: complete.sequence, description: "expired countdown shortcut cannot restart before reset") {
                $0.timerFocused("Pause stopwatch") && $0.timerButton("Resume countdown", enabled: false)
                    && $0.timerElapsed("27 seconds") && $0.timerRemaining("0 seconds")
            }
            #expect(refused.timerContains("Complete"))
            try await focusTimer("Reset countdown", session: session, recorder: recorder)
            session.send(.key(.return))
            let reset = try await recorder.wait(after: refused.sequence, description: "native countdown Reset restores its limit without resetting stopwatch") {
                $0.timerFocused("Reset countdown") && $0.timerButton("Start countdown")
                    && $0.timerRemaining("20 seconds") && $0.timerElapsed("27 seconds") && $0.timerButton("Pause stopwatch")
            }
            session.sendInput(Array("cr\t".utf8))
            _ = try await recorder.wait(after: reset.sequence, description: "reset-both shortcut replaces both current values atomically") {
                $0.timerFocused("Start stopwatch") && $0.timerButton("Start stopwatch") && $0.timerButton("Start countdown")
                    && $0.timerElapsed("0 seconds") && $0.timerRemaining("20 seconds")
            }
        }
    }

    @Test("Expiry first observed during compact resize pauses countdown and reset can start a fresh interval")
    func expiryDuringResize() async throws {
        let clock = TimerTestClock()
        try await withTimer(now: { clock.instant }) { session, surface, recorder in
            let initial = try await recorder.wait(description: "countdown-only resize scenario starts paused") {
                $0.timerFocused("Start stopwatch") && $0.timerButton("Start countdown")
                    && $0.timerElapsed("0 seconds") && $0.timerRemaining("20 seconds")
            }
            session.send(.key(.character("c")))
            let running = try await recorder.wait(after: initial.sequence, description: "only countdown is running before the first expiry observation") {
                $0.timerButton("Pause countdown") && $0.timerButton("Start stopwatch")
                    && $0.timerElapsed("0 seconds") && $0.timerRemaining("20 seconds")
            }
            // These changes happen without yielding or rendering an intermediate expiry frame.
            clock.advance(by: .seconds(21))
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let expired = try await recorder.wait(after: running.sequence, description: "expiry observed in the resized layout pauses countdown rather than leaving its schedule running") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.timerContains("Complete")
                    && $0.timerButton("Resume countdown", enabled: false)
                    && !$0.timerButton("Pause countdown", enabled: false)
                    && $0.timerButton("Start stopwatch") && $0.timerElapsed("0 seconds") && $0.timerRemaining("0 seconds")
            }
            try await focusTimer("Reset countdown", session: session, recorder: recorder)
            // Reset and restart share a read. A completion observer must not pause
            // the replacement countdown merely because an old frame had expired.
            session.sendInput(Array("rc\t".utf8))
            let restarted = try await recorder.wait(after: expired.sequence, description: "reset plus immediate restart retains the replacement countdown") {
                $0.timerFocused("Start stopwatch") && $0.timerButton("Pause countdown")
                    && $0.timerElapsed("0 seconds") && $0.timerRemaining("20 seconds")
                    && !$0.timerContains("Complete")
            }
            clock.advance(by: .seconds(1))
            session.requestSurfaceRefresh()
            _ = try await recorder.wait(after: restarted.sequence, description: "the fresh countdown still advances after prior completion callbacks") {
                $0.timerButton("Pause countdown") && $0.timerRemaining("19 seconds")
                    && $0.timerButton("Start stopwatch") && $0.timerElapsed("0 seconds")
            }
        }
    }

    @Test("Default clock advances through the native TimelineView after native Start")
    func liveTimeline() async throws {
        try await withTimer { session, _, recorder in
            let initial = try await recorder.wait(description: "live stopwatch starts paused with native button focus") {
                $0.timerFocused("Start stopwatch") && $0.timerElapsed("0 seconds")
            }
            session.send(.key(.return))
            _ = try await recorder.wait(after: initial.sequence, description: "native timeline displays positive live elapsed time without requested refresh") {
                $0.timerButton("Pause stopwatch") && $0.timerRemaining("20 seconds")
                    && $0.semantics.accessibilityNodes.contains {
                        $0.label?.hasPrefix("Elapsed time: ") == true && $0.label != "Elapsed time: 0 seconds"
                    }
            }
        }
    }
}

/// Explicit clock input is a mutable test resource, not application timer state.
@MainActor
private final class TimerTestClock {
    private(set) var instant = MonotonicInstant.zero

    func advance(by duration: Duration) {
        instant = instant.advanced(by: duration)
    }
}

private struct TimerTestApp {
    let now: @MainActor () -> MonotonicInstant

    nonisolated init() {
        now = { .now() }
    }

    nonisolated init(now: @escaping @MainActor () -> MonotonicInstant) {
        self.now = now
    }
}

extension TimerTestApp: App {
    var body: some Scene {
        WindowGroup(id: "timer-tests") { TimerExampleView(now: now) }.exitOnKeys([])
    }
}

@MainActor
private func withTimer(
    now: @escaping @MainActor () -> MonotonicInstant = { .now() },
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: TimerTestApp(now: now), sceneID: "timer-tests", surface: surface)
    let run = Task { try await session.start() }
    do {
        try await perform(session, surface, recorder)
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        if case .failure(let runError) = await run.result {
            Issue.record("Hosted timer failed: \(runError)")
        }
        throw error
    }
}

@MainActor
private func focusTimer(
    _ label: String, session: HostedSceneSession, recorder: HostedFrameRecorder
) async throws {
    var frame = try await recorder.wait(description: "current timer focus") { $0.focusedIdentity != nil }
    for _ in 0..<6 {
        if frame.timerFocused(label) { return }
        let previousFocus = frame.focusedIdentity
        session.send(.key(.tab))
        frame = try await recorder.wait(after: frame.sequence, description: "native Tab advances timer focus") {
            $0.focusedIdentity != nil && $0.focusedIdentity != previousFocus
        }
    }
    throw TimerTestFailure.focusNotReached(label)
}

private enum TimerTestFailure: Error {
    case focusNotReached(String)
}

private extension SemanticHostFrame {
    func timerContains(_ value: String) -> Bool { raster.lines.contains { $0.contains(value) } }

    func timerFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == .button && $0.label == label
        }
    }

    func timerButton(_ label: String, enabled: Bool = true) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .button && $0.label == label && $0.isEnabled == enabled }
    }

    func timerElapsed(_ spoken: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.label == "Elapsed time: \(spoken)" }
    }

    func timerRemaining(_ spoken: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.label == "Remaining time: \(spoken)" }
    }
}
