import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
struct DurationTextTests {
    @Test("Original and styled initializers remain usable as main-actor function references")
    func initializerReferences() {
        let makeElapsed: @MainActor (Duration) -> DurationText = DurationText.init(elapsed:)
        let makeRemaining: @MainActor (Duration) -> DurationText = DurationText.init(remaining:)
        let makeStyledElapsed: @MainActor (Duration, InstrumentReadout.Style) -> DurationText = DurationText.init(elapsed:style:)
        let makeStyledRemaining: @MainActor (Duration, InstrumentReadout.Style) -> DurationText = DurationText.init(remaining:style:)
        let duration = Duration.milliseconds(59_001)
        let proposal = ProposedSize(width: nil, height: nil)
        let elapsed = DefaultRenderer().render(makeElapsed(duration), proposal: proposal)
        let remaining = DefaultRenderer().render(makeRemaining(duration), proposal: proposal)
        #expect(elapsed.rasterSurface.lines == ["0:59"])
        #expect(remaining.rasterSurface.lines == ["1:00"])
        #expect(DefaultRenderer().render(makeStyledElapsed(duration, .plain), proposal: proposal).rasterSurface
                == elapsed.rasterSurface)
        #expect(DefaultRenderer().render(makeStyledRemaining(duration, .plain), proposal: proposal).rasterSurface
                == remaining.rasterSurface)
        let segmentedElapsed = DefaultRenderer().render(makeStyledElapsed(duration, .segmented), proposal: proposal)
        let segmentedRemaining = DefaultRenderer().render(makeStyledRemaining(duration, .segmented), proposal: proposal)
        #expect(segmentedElapsed.rasterSurface.size.height == 3)
        #expect(segmentedRemaining.rasterSurface.size.height == 3)
        #expect(segmentedElapsed.semanticSnapshot.accessibilityNodes.compactMap(\.label) == ["Elapsed time: 59 seconds"])
        #expect(segmentedRemaining.semanticSnapshot.accessibilityNodes.compactMap(\.label) == ["Remaining time: 1 minute"])
    }

    @Test("Both public initializers reject durations outside the supported range")
    func invalidDurations() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                _ = DurationText(elapsed: Duration(secondsComponent: 0, attosecondsComponent: -1))
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                _ = DurationText(remaining: Duration(secondsComponent: Int64.max, attosecondsComponent: 1))
            }
        }
    }

    @Test("Elapsed time floors and remaining time ceils at exact second, minute and hour boundaries")
    func rounding() {
        let fixtures: [(Duration, String, String)] = [
            (.zero, "0:00", "0:00"),
            (Duration(secondsComponent: 0, attosecondsComponent: 1), "0:00", "0:01"),
            (.milliseconds(999), "0:00", "0:01"),
            (.seconds(1), "0:01", "0:01"),
            (Duration(secondsComponent: 1, attosecondsComponent: 1), "0:01", "0:02"),
            (.seconds(59), "0:59", "0:59"),
            (.milliseconds(59_001), "0:59", "1:00"),
            (.seconds(60), "1:00", "1:00"),
            (.milliseconds(3_599_999), "59:59", "1:00:00"),
            (.seconds(3_600), "1:00:00", "1:00:00"),
            (.seconds(3_661), "1:01:01", "1:01:01"),
            (.seconds(86_400), "24:00:00", "24:00:00"),
            (Duration(secondsComponent: Int64.max, attosecondsComponent: -1),
             "2562047788015215:30:06", "2562047788015215:30:07"),
            (.seconds(Int64.max), "2562047788015215:30:07", "2562047788015215:30:07"),
        ]
        for (duration, elapsed, remaining) in fixtures {
            let elapsedSurface = DefaultRenderer().render(
                DurationText(elapsed: duration), proposal: ProposedSize(width: nil, height: nil)
            ).rasterSurface
            let remainingSurface = DefaultRenderer().render(
                DurationText(remaining: duration), proposal: ProposedSize(width: nil, height: nil)
            ).rasterSurface
            #expect(elapsedSurface.lines == [elapsed])
            #expect(remainingSurface.lines == [remaining])
            #expect(elapsedSurface.size.width == elapsed.count)
            #expect(remainingSurface.size.width == remaining.count)
            #expect(elapsedSurface.size.height == 1)
            #expect(remainingSurface.size.height == 1)
        }
    }

    @Test("Accessibility labels speak the displayed units and distinguish elapsed from remaining time")
    func semantics() {
        let fixtures: [(Duration, String, String)] = [
            (.zero, "Elapsed time: 0 seconds", "Remaining time: 0 seconds"),
            (Duration(secondsComponent: 0, attosecondsComponent: 1),
             "Elapsed time: 0 seconds", "Remaining time: 1 second"),
            (.milliseconds(59_001), "Elapsed time: 59 seconds", "Remaining time: 1 minute"),
            (.seconds(3_661), "Elapsed time: 1 hour, 1 minute, 1 second",
             "Remaining time: 1 hour, 1 minute, 1 second"),
            (.seconds(86_402), "Elapsed time: 24 hours, 2 seconds", "Remaining time: 24 hours, 2 seconds"),
        ]
        for (duration, elapsed, remaining) in fixtures {
            let elapsedResult = DefaultRenderer().render(
                DurationText(elapsed: duration), proposal: ProposedSize(width: 32, height: 1)
            )
            let remainingResult = DefaultRenderer().render(
                DurationText(remaining: duration), proposal: ProposedSize(width: 32, height: 1)
            )
            #expect(elapsedResult.semanticSnapshot.accessibilityNodes.compactMap(\.label) == [elapsed])
            #expect(remainingResult.semanticSnapshot.accessibilityNodes.compactMap(\.label) == [remaining])
            #expect(elapsedResult.semanticSnapshot.focusRegions.isEmpty)
            #expect(remainingResult.semanticSnapshot.focusRegions.isEmpty)
        }
    }

    @Test("Segmented durations retain exact rounding and unbounded hours, with native fallback")
    func segmentedRounding() {
        let fixtures: [(Duration, String, String, String, String)] = [
            (.zero, "0:00", "0:00", "Elapsed time: 0 seconds", "Remaining time: 0 seconds"),
            (Duration(secondsComponent: 0, attosecondsComponent: 1), "0:00", "0:01",
             "Elapsed time: 0 seconds", "Remaining time: 1 second"),
            (.milliseconds(59_001), "0:59", "1:00",
             "Elapsed time: 59 seconds", "Remaining time: 1 minute"),
            (.milliseconds(3_599_999), "59:59", "1:00:00",
             "Elapsed time: 59 minutes, 59 seconds", "Remaining time: 1 hour"),
            (.seconds(86_400), "24:00:00", "24:00:00",
             "Elapsed time: 24 hours", "Remaining time: 24 hours"),
            (Duration(secondsComponent: Int64.max, attosecondsComponent: -1),
             "2562047788015215:30:06", "2562047788015215:30:07",
             "Elapsed time: 2562047788015215 hours, 30 minutes, 6 seconds",
             "Remaining time: 2562047788015215 hours, 30 minutes, 7 seconds"),
            (.seconds(Int64.max), "2562047788015215:30:07", "2562047788015215:30:07",
             "Elapsed time: 2562047788015215 hours, 30 minutes, 7 seconds",
             "Remaining time: 2562047788015215 hours, 30 minutes, 7 seconds"),
        ]
        for (duration, elapsed, remaining, elapsedLabel, remainingLabel) in fixtures {
            for proposal in [ProposedSize(width: nil, height: nil),
                             ProposedSize(width: 100, height: 3),
                             ProposedSize(width: 12, height: 3),
                             ProposedSize(width: 32, height: 1)] {
                let elapsedResult = DefaultRenderer().render(
                    DurationText(elapsed: duration, style: .segmented), proposal: proposal)
                let remainingResult = DefaultRenderer().render(
                    DurationText(remaining: duration, style: .segmented), proposal: proposal)
                #expect(elapsedResult.rasterSurface == DefaultRenderer().render(
                    InstrumentReadout(elapsed), proposal: proposal).rasterSurface)
                #expect(remainingResult.rasterSurface == DefaultRenderer().render(
                    InstrumentReadout(remaining), proposal: proposal).rasterSurface)
                #expect(elapsedResult.semanticSnapshot.accessibilityNodes.compactMap(\.label) == [elapsedLabel])
                #expect(remainingResult.semanticSnapshot.accessibilityNodes.compactMap(\.label) == [remainingLabel])
                #expect(elapsedResult.semanticSnapshot.focusRegions.isEmpty)
                #expect(remainingResult.semanticSnapshot.focusRegions.isEmpty)
            }
        }
    }

    @Test("Duration styles inherit accent and callers can replace the spoken label before theme composition")
    func segmentedThemeAndOverride() {
        let custom = ChioTheme.default.replacing(
            colors: ChioTheme.default.colors.replacing(accent: Color(hexRGB: 0x123456)))
        for theme in [ChioTheme.default, .light, .btop, custom] {
            for style in [InstrumentReadout.Style.plain, .segmented] {
                for proposal in [ProposedSize(width: 32, height: 3), ProposedSize(width: 8, height: 1)] {
                    let result = DefaultRenderer().render(
                        DurationText(remaining: .milliseconds(1), style: style)
                            .accessibilityLabel("Cooldown: one second").chioTheme(theme),
                        proposal: proposal)
                    #expect(result.semanticSnapshot.accessibilityNodes.compactMap(\.label) == ["Cooldown: one second"])
                    #expect(result.semanticSnapshot.focusRegions.isEmpty)
                    let painted = result.rasterSurface.cells.flatMap { $0 }.filter { $0.character != " " }
                    #expect(!painted.isEmpty)
                    #expect(painted.allSatisfy { $0.style?.foregroundColor == theme.colors.accent })
                }
            }
        }
    }

    @Test("An outer aggregate label preserves the native semantics of explicitly named descendant text")
    func outerAggregateLabel() {
        let proposal = ProposedSize(width: 32, height: 3)
        let native = DefaultRenderer().render(
            Text(verbatim: "0:01").accessibilityLabel("Remaining time: 1 second")
                .chioTheme(.btop).accessibilityLabel("Cooldown"), proposal: proposal)
        #expect(native.semanticSnapshot.accessibilityNodes.compactMap(\.label)
                == ["Cooldown", "Remaining time: 1 second"])
        for style in [InstrumentReadout.Style.plain, .segmented] {
            let result = DefaultRenderer().render(
                DurationText(remaining: .milliseconds(1), style: style)
                    .chioTheme(.btop).accessibilityLabel("Cooldown"), proposal: proposal)
            #expect(result.semanticSnapshot.accessibilityNodes.compactMap(\.label)
                    == native.semanticSnapshot.accessibilityNodes.compactMap(\.label))
        }
    }

    @Test("Both duration roles use the current accent without assigning completion meaning", arguments: [false, true])
    func theme(light: Bool) {
        let base: ChioTheme = light ? .light : .default
        let themes = [base, base.replacing(colors: base.colors.replacing(accent: Color(hexRGB: 0x123456)))]
        for theme in themes {
            for duration in [Duration.zero, .seconds(65)] {
                let elapsed = DefaultRenderer().render(
                    DurationText(elapsed: duration).chioTheme(theme),
                    proposal: ProposedSize(width: nil, height: nil)
                ).rasterSurface
                let remaining = DefaultRenderer().render(
                    DurationText(remaining: duration).chioTheme(theme),
                    proposal: ProposedSize(width: nil, height: nil)
                ).rasterSurface
                #expect(elapsed == remaining)
                #expect(elapsed.lines == [duration == .zero ? "0:00" : "1:05"])
                let cells = elapsed.cells.flatMap { $0 }
                #expect(!cells.isEmpty)
                #expect(cells.allSatisfy { $0.style?.foregroundColor == theme.colors.accent })
            }
        }
    }
}
