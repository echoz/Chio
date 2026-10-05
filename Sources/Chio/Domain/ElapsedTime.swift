import SwiftTUIViews

/// Elapsed time accumulated across explicitly started and paused intervals.
///
/// The caller supplies instants from the same monotonic clock lifetime, in
/// chronological order for transitions. Queries do not record observations.
/// Duration differences and accumulated totals must be representable by Swift's
/// `Duration`; its standard arithmetic preconditions apply.
///
/// This value neither reads a clock nor schedules updates. Running anchors are
/// process-relative, so the value has no persistence representation.
public struct ElapsedTime {
    private let accumulated: Duration
    private let phase: Phase

    fileprivate enum Phase {
        case paused
        case running(since: MonotonicInstant)
    }

    /// Starts paused with zero elapsed time.
    public init() {
        accumulated = .zero
        phase = .paused
    }

    private init(accumulated: Duration, phase: Phase) {
        self.accumulated = accumulated
        self.phase = phase
    }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// Returns accumulated time plus the current running interval.
    /// An instant earlier than its running anchor contributes zero.
    public func elapsed(at instant: MonotonicInstant) -> Duration {
        guard case let .running(since) = phase, instant >= since else {
            return accumulated
        }
        return accumulated + since.duration(to: instant)
    }

    /// Starts another interval, retaining accumulated time. Already running is inert.
    public func resumed(at instant: MonotonicInstant) -> Self {
        guard !isRunning else { return self }
        return Self(accumulated: accumulated, phase: .running(since: instant))
    }

    /// Accumulates the current interval and pauses.
    /// Already paused, or an instant earlier than the running anchor, is inert.
    public func paused(at instant: MonotonicInstant) -> Self {
        guard case let .running(since) = phase, instant >= since else { return self }
        return Self(accumulated: elapsed(at: instant), phase: .paused)
    }

    /// Clears accumulated time and returns to paused.
    public func resetting() -> Self { Self() }
}

extension ElapsedTime: Hashable {}

extension ElapsedTime: Sendable {}

extension ElapsedTime.Phase: Hashable {}

extension ElapsedTime.Phase: Sendable {}
