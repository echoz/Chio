import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
struct DurationTextTests {
    @Test("Both public initializers reject durations outside the supported range")
    func invalidDurations() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                _ = DurationText(elapsed: .init(secondsComponent: 0, attosecondsComponent: -1))
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                _ = DurationText(remaining: .init(secondsComponent: Int64.max, attosecondsComponent: 1))
            }
        }
    }

    @Test("Elapsed time floors and remaining time ceils at exact second, minute and hour boundaries")
    func rounding() {
        let fixtures: [(Duration, String, String)] = [
            (.zero, "0:00", "0:00"),
            (.init(secondsComponent: 0, attosecondsComponent: 1), "0:00", "0:01"),
            (.milliseconds(999), "0:00", "0:01"),
            (.seconds(1), "0:01", "0:01"),
            (.init(secondsComponent: 1, attosecondsComponent: 1), "0:01", "0:02"),
            (.seconds(59), "0:59", "0:59"),
            (.milliseconds(59_001), "0:59", "1:00"),
            (.seconds(60), "1:00", "1:00"),
            (.milliseconds(3_599_999), "59:59", "1:00:00"),
            (.seconds(3_600), "1:00:00", "1:00:00"),
            (.seconds(3_661), "1:01:01", "1:01:01"),
            (.seconds(86_400), "24:00:00", "24:00:00"),
            (.init(secondsComponent: Int64.max, attosecondsComponent: -1),
             "2562047788015215:30:06", "2562047788015215:30:07"),
            (.seconds(Int64.max), "2562047788015215:30:07", "2562047788015215:30:07"),
        ]
        for (duration, elapsed, remaining) in fixtures {
            let elapsedSurface = DefaultRenderer().render(
                DurationText(elapsed: duration), proposal: .init(width: nil, height: nil)
            ).rasterSurface
            let remainingSurface = DefaultRenderer().render(
                DurationText(remaining: duration), proposal: .init(width: nil, height: nil)
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
            (.init(secondsComponent: 0, attosecondsComponent: 1),
             "Elapsed time: 0 seconds", "Remaining time: 1 second"),
            (.milliseconds(59_001), "Elapsed time: 59 seconds", "Remaining time: 1 minute"),
            (.seconds(3_661), "Elapsed time: 1 hour, 1 minute, 1 second",
             "Remaining time: 1 hour, 1 minute, 1 second"),
            (.seconds(86_402), "Elapsed time: 24 hours, 2 seconds", "Remaining time: 24 hours, 2 seconds"),
        ]
        for (duration, elapsed, remaining) in fixtures {
            let elapsedResult = DefaultRenderer().render(
                DurationText(elapsed: duration), proposal: .init(width: 32, height: 1)
            )
            let remainingResult = DefaultRenderer().render(
                DurationText(remaining: duration), proposal: .init(width: 32, height: 1)
            )
            #expect(elapsedResult.semanticSnapshot.accessibilityNodes.compactMap(\.label) == [elapsed])
            #expect(remainingResult.semanticSnapshot.accessibilityNodes.compactMap(\.label) == [remaining])
            #expect(elapsedResult.semanticSnapshot.focusRegions.isEmpty)
            #expect(remainingResult.semanticSnapshot.focusRegions.isEmpty)
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
                    proposal: .init(width: nil, height: nil)
                ).rasterSurface
                let remaining = DefaultRenderer().render(
                    DurationText(remaining: duration).chioTheme(theme),
                    proposal: .init(width: nil, height: nil)
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
