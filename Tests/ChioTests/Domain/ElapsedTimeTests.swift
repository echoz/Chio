import Chio
import SwiftTUIViews
import Testing

struct ElapsedTimeTests {
    @Test("A new value is paused at zero regardless of the supplied instant")
    func initialValue() {
        let initial = ElapsedTime()
        #expect(!initial.isRunning)
        #expect(initial.elapsed(at: instant(.seconds(-10))) == .zero)
        #expect(initial.elapsed(at: instant(.seconds(100))) == .zero)
        #expect(initial.paused(at: instant(.seconds(100))) == initial)
        #expect(initial.resetting() == initial)
    }

    @Test("Running elapsed time derives from explicit instants and preserves fractions")
    func runningInterval() {
        let initial = ElapsedTime()
        let running = initial.resumed(at: instant(.seconds(10)))
        #expect(running.isRunning)
        #expect(running.elapsed(at: instant(.seconds(10))) == .zero)
        #expect(running.elapsed(at: instant(.milliseconds(12_750))) == .milliseconds(2_750))
        #expect(!initial.isRunning)
        #expect(initial.elapsed(at: instant(.seconds(100))) == .zero)
        #expect(initial == ElapsedTime())
    }

    @Test("Multiple running intervals accumulate while paused gaps contribute nothing")
    func accumulatedIntervals() {
        let firstRun = ElapsedTime().resumed(at: instant(.seconds(10)))
        let firstPause = firstRun.paused(at: instant(.milliseconds(12_750)))
        #expect(!firstPause.isRunning)
        #expect(firstPause.elapsed(at: instant(.seconds(1_000))) == .milliseconds(2_750))
        let secondRun = firstPause.resumed(at: instant(.seconds(20)))
        #expect(secondRun.elapsed(at: instant(.milliseconds(25_250))) == .seconds(8))
        let secondPause = secondRun.paused(at: instant(.milliseconds(24_250)))
        #expect(!secondPause.isRunning)
        #expect(secondPause.elapsed(at: instant(.seconds(100))) == .seconds(7))
        #expect(firstRun.isRunning)
        #expect(firstRun.elapsed(at: instant(.milliseconds(12_750))) == .milliseconds(2_750))
        #expect(firstPause.elapsed(at: instant(.seconds(100))) == .milliseconds(2_750))
        #expect(secondRun.isRunning)
        #expect(secondRun.elapsed(at: instant(.milliseconds(24_250))) == .seconds(7))
    }

    @Test("Repeated resume and pause preserve the existing interval or frozen value")
    func repeatedTransitions() {
        let running = ElapsedTime().resumed(at: instant(.seconds(10)))
        #expect(running.resumed(at: instant(.seconds(200))) == running)
        #expect(running.resumed(at: instant(.seconds(5))) == running)
        #expect(running.elapsed(at: instant(.seconds(12))) == .seconds(2))
        let paused = running.paused(at: instant(.seconds(12)))
        #expect(paused.paused(at: instant(.seconds(500))) == paused)
        #expect(paused.paused(at: instant(.seconds(5))) == paused)
        #expect(paused.elapsed(at: instant(.seconds(500))) == .seconds(2))
    }

    @Test("Stale queries contribute zero and stale pause cannot end the current interval")
    func staleInstants() {
        let accumulated = ElapsedTime().resumed(at: instant(.zero))
            .paused(at: instant(.seconds(2)))
        let running = accumulated.resumed(at: instant(.seconds(10)))
        #expect(running.elapsed(at: instant(.seconds(9))) == .seconds(2))
        #expect(running.elapsed(at: instant(.seconds(10))) == .seconds(2))
        #expect(running.paused(at: instant(.seconds(9))) == running)
        #expect(running.isRunning)
        #expect(running.elapsed(at: instant(.seconds(12))) == .seconds(4))
        let atAnchor = running.paused(at: instant(.seconds(10)))
        #expect(!atAnchor.isRunning)
        #expect(atAnchor.elapsed(at: instant(.seconds(100))) == .seconds(2))

        let distant = ElapsedTime().resumed(at: instant(.seconds(Int64.max)))
        #expect(distant.elapsed(at: instant(.seconds(Int64.min))) == .zero)
        #expect(distant.paused(at: instant(.seconds(Int64.min))) == distant)
    }

    @Test("Queries record no last observation and do not alter a later transition")
    func independentQueries() {
        let running = ElapsedTime().resumed(at: instant(.seconds(10)))
        #expect(running.elapsed(at: instant(.seconds(30))) == .seconds(20))
        #expect(running.elapsed(at: instant(.seconds(12))) == .seconds(2))
        let paused = running.paused(at: instant(.seconds(15)))
        #expect(paused.elapsed(at: instant(.seconds(100))) == .seconds(5))
        #expect(running.elapsed(at: instant(.seconds(30))) == .seconds(20))
    }

    @Test("Reset clears either a running or paused value without changing the original", arguments: [false, true])
    func reset(running: Bool) {
        let started = ElapsedTime().resumed(at: instant(.seconds(10)))
        let original = running ? started : started.paused(at: instant(.seconds(15)))
        let reset = original.resetting()
        #expect(reset == ElapsedTime())
        #expect(!reset.isRunning)
        #expect(reset.elapsed(at: instant(.seconds(100))) == .zero)
        #expect(original.isRunning == running)
        #expect(original.elapsed(at: instant(.seconds(20))) == (running ? .seconds(10) : .seconds(5)))
        let restarted = reset.resumed(at: instant(.seconds(100)))
        #expect(restarted.elapsed(at: instant(.seconds(102))) == .seconds(2))
    }

    @Test("A long gap needs no ticks or intermediate observations")
    func longGap() {
        let running = ElapsedTime().resumed(at: instant(.seconds(3)))
        let paused = running.paused(at: instant(.seconds(1_000_000_000_003)))
        #expect(paused.elapsed(at: instant(.seconds(1_000_000_000_100))) == .seconds(1_000_000_000_000))
        let resumed = paused.resumed(at: instant(.seconds(1_000_000_000_200)))
        #expect(resumed.elapsed(at: instant(.milliseconds(1_000_000_000_201_500)))
            == .milliseconds(1_000_000_000_001_500))
    }

    @Test("Value equality includes the running anchor and retained accumulated duration")
    func valueSemantics() {
        var origin = instant(.seconds(10))
        let running = ElapsedTime().resumed(at: origin)
        origin.offset = .seconds(100)
        #expect(running.elapsed(at: instant(.seconds(12))) == .seconds(2))
        #expect(running == ElapsedTime().resumed(at: instant(.seconds(10))))
        #expect(running != ElapsedTime().resumed(at: instant(.seconds(11))))
        let paused = running.paused(at: instant(.seconds(12)))
        let equalPause = ElapsedTime().resumed(at: instant(.seconds(50)))
            .paused(at: instant(.seconds(52)))
        #expect(paused == equalPause)
        #expect(paused != ElapsedTime())
        #expect(Set([paused, equalPause]).count == 1)
    }

    private func instant(_ offset: Duration) -> MonotonicInstant {
        MonotonicInstant(offset: offset)
    }
}
