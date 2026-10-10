import Chio
import SwiftTUI

@MainActor
struct TimerExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var themeChoice: ExampleTheme
    @State private var stopwatch = ElapsedTime()
    @State private var countdown = ElapsedTime()

    private let countdownDuration: Duration
    // An application clock boundary shared by observation and input dispatch.
    // Tests can supply explicit instants while retaining the real native timeline.
    private let now: @MainActor () -> MonotonicInstant

    init(theme: ExampleTheme = .default, countdownDuration: Duration = .seconds(20),
         now: @escaping @MainActor () -> MonotonicInstant = { .now() }) {
        precondition(countdownDuration > .zero && countdownDuration <= .seconds(Int64.max))
        _themeChoice = State(wrappedValue: theme)
        self.countdownDuration = countdownDuration
        self.now = now
    }

    private var theme: ChioTheme { themeChoice.theme }

    private func toggleStopwatch() {
        let instant = now()
        stopwatch = stopwatch.isRunning ? stopwatch.paused(at: instant) : stopwatch.resumed(at: instant)
    }

    private func toggleCountdown() {
        let instant = now()
        guard countdown.elapsed(at: instant) < countdownDuration else { return }
        countdown = countdown.isRunning ? countdown.paused(at: instant) : countdown.resumed(at: instant)
    }

    private func actionLabel(for value: ElapsedTime, at instant: MonotonicInstant) -> String {
        if value.isRunning { return "Pause" }
        if value.elapsed(at: instant) == .zero { return "Start" }
        return "Resume"
    }

    private var hints: some View {
        KeyHints {
            KeyHint("s", "stopwatch")
            KeyHint("c", "countdown")
            KeyHint("r", "reset both")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }

    private func stopwatchPanel(at instant: MonotonicInstant, isCompact: Bool) -> some View {
        GroupBox("Stopwatch") {
            VStack(alignment: .leading, spacing: isCompact ? 0 : 1) {
                HStack {
                    DurationText(elapsed: stopwatch.elapsed(at: instant))
                    Spacer(minLength: 1)
                    Text(stopwatch.isRunning ? "Running" : "Paused")
                        .foregroundStyle(stopwatch.isRunning ? theme.colors.success : theme.colors.mutedText)
                }
                if !isCompact {
                    Text("Keep time across pauses.").foregroundStyle(theme.colors.secondaryText)
                }
                HStack(spacing: 1) {
                    Button(actionLabel(for: stopwatch, at: instant), action: toggleStopwatch)
                        .accessibilityLabel("\(actionLabel(for: stopwatch, at: instant)) stopwatch")
                    Button("Reset") { stopwatch = stopwatch.resetting() }
                        .accessibilityLabel("Reset stopwatch")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func countdownPanel(at instant: MonotonicInstant, isCompact: Bool) -> some View {
        let elapsed = countdown.elapsed(at: instant)
        let isComplete = elapsed >= countdownDuration
        let remaining = isComplete ? Duration.zero : countdownDuration - elapsed
        let status: String
        if isComplete { status = "Complete" }
        else if countdown.isRunning { status = "Running" }
        else { status = "Paused" }
        return GroupBox("Countdown") {
            VStack(alignment: .leading, spacing: isCompact ? 0 : 1) {
                HStack {
                    DurationText(remaining: remaining)
                    Spacer(minLength: 1)
                    Text(status)
                        .foregroundStyle(isComplete ? theme.colors.success : theme.colors.mutedText)
                }
                if !isCompact {
                    Text(isComplete ? "Time is up. Ready for another round." : "A short focus interval. No alarm or background job.")
                        .foregroundStyle(theme.colors.secondaryText)
                }
                ProgressView(value: isComplete ? 1 : elapsed.totalSeconds / countdownDuration.totalSeconds,
                             barWidth: max(1, min(38, (terminalSize.width >= 70 ? min(100, terminalSize.width) / 2 : terminalSize.width) - 8))) {
                    EmptyView()
                } currentValueLabel: { EmptyView() }
                HStack(spacing: 1) {
                    Button(actionLabel(for: countdown, at: instant), action: toggleCountdown)
                        .accessibilityLabel("\(actionLabel(for: countdown, at: instant)) countdown")
                        .disabled(isComplete)
                    Button("Reset") { countdown = countdown.resetting() }
                        .accessibilityLabel("Reset countdown")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: isComplete && countdown.isRunning, initial: true) { _, finished in
            guard finished else { return }
            // Recheck the retained value at dispatch: a reset may have superseded
            // this displayed completion before its lifecycle callback runs.
            let current = countdown
            let observed = now()
            if current.isRunning && current.elapsed(at: observed) >= countdownDuration {
                countdown = current.paused(at: observed)
            }
        }
    }

    private func content(at instant: MonotonicInstant) -> some View {
        let isCompact = terminalSize.width < 70 || terminalSize.height < 24
        let layout: AnyLayout
        if terminalSize.width >= 70 {
            layout = AnyLayout(HStackLayout(alignment: .top, spacing: 2))
        } else {
            let panelSpacing = isCompact ? 0 : 1
            layout = AnyLayout(VStackLayout(alignment: .leading, spacing: panelSpacing))
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ time studio").foregroundStyle(theme.colors.secondaryText)
            }
            if !isCompact {
                Text("Every second counts. Pauses do not.").foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            layout {
                stopwatchPanel(at: instant, isCompact: isCompact)
                    .frame(width: terminalSize.width >= 70 ? (min(100, terminalSize.width) - 4) / 2 : nil)
                countdownPanel(at: instant, isCompact: isCompact)
                    .frame(width: terminalSize.width >= 70 ? (min(100, terminalSize.width) - 4) / 2 : nil)
            }
            .groupBoxStyle(ChioGroupBoxStyle(theme: theme.replacing(
                spacing: theme.spacing.replacing(sectionGap: isCompact ? 0 : theme.spacing.sectionGap)
            )))
            Spacer(minLength: 0)
            if !isCompact {
                Text("Tab moves focus · Return activates · each clock has its own controls")
                    .foregroundStyle(theme.colors.mutedText)
                StatusBar { hints }
            } else { hints }
        }
        .padding(isCompact ? 0 : 1)
        .frame(maxWidth: 100, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
    }
}

extension TimerExampleView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: .seconds(1),
                                paused: !stopwatch.isRunning && !countdown.isRunning)) { _ in
            content(at: now())
        }
        .onKeyPress { press in
            if press.modifiers == .ctrl {
                switch press.key {
                case .character("t"): themeChoice = themeChoice.next
                case .character("q"): _ = requestTermination()
                default: return .ignored
                }
            } else if press.modifiers.isEmpty {
                switch press.key {
                case .character("s"): toggleStopwatch()
                case .character("c"): toggleCountdown()
                case .character("r"):
                    stopwatch = stopwatch.resetting()
                    countdown = countdown.resetting()
                default: return .ignored
                }
            } else { return .ignored }
            return .handled
        }
        .chioTheme(theme)
    }
}
