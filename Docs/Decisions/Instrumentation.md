# Compact instrumentation and duration display

**Status:** Accepted presentation contracts. Compact styles, `Sparkline` and plain
`DurationText` shipped in 0.1.0; measurement gauges and segmented readouts extend
those contracts and have not yet been included in a tagged release.

Present supplied measurements and durations; applications retain sampling, timing and interpretation.

## Compact instrumentation

`ChioTheme.btop` uses near-black/cyan semantic roles and native strokes, without
a palette dependency or separate component family.

`ChioGroupBoxStyle(titlePlacement: .border)` overlays a passive, single-row title
on the top border. It truncates to allocation, preserves corners and omits title
paint below five columns. The authored label stays mounted across resizing; only
its focus/hit testing are disabled. Content remains native and enabled. `.content`
is the default; native sizing and ancestor clipping still apply.

`ChioProgressViewStyle(treatment: .measurement)` uses accent for every determinate
value, including 100%; default `.progress` uses success at completion. Native
fraction, labels and indeterminate behavior are shared. Accessibility remains a
normalized progress bar; applications own units, thresholds and meaning.

`Sparkline` draws one passive series with native Canvas/braille packing. Slots are
equally spaced, oldest to newest. `nil` is a missing reading that breaks the line,
distinct from zero or an omitted slot. Construction rejects nonfinite readings
and fixed bounds that are nonfinite or not strictly increasing. Serializable
`Scale` is input configuration, validated when consumed by the view.

Automatic scale uses finite extrema; constant series sit at the midpoint.
Empty/all-missing series draw nothing. A single-entry series sits on the right;
a lone reading among gaps retains its slot. Fixed scales clip outliers.
Overflow-safe normalization handles extreme finite bounds; drawing coordinates
are bounded before submission.

Narrow reduction retains first/last/minimum/maximum in chronological order per
drawing column within each contiguous run. Gaps disconnect runs even within one
column, although subcolumn gaps may not be visibly distinct. Every draw scans
input, so applications bound history retention. Native image semantics provide
a count/latest/extrema summary that applications can replace to include units.
Chio owns no sampler, clock, monitoring state or alert policy. Native overlapping
subcell writes share one cell's paint; independently colored overlaps are unclaimed.

## Measurement gauges and numeric readouts

`MeasurementGauge(position:style:)` presents an application-normalized position.
A known position must be finite and in `0...1`; construction traps otherwise.
`nil` means a missing reading, distinct from zero. Applications own scale
normalization, units, thresholds, out-of-range policy and surrounding labels.
The view owns no sampler, clock or monitoring state.

`.bar` is the default and uses one row; `.dial` uses up to five rows. Both use
native Canvas, prefer twenty columns and bound drawing to 512 columns. Missing
bars show dots and missing dials retain their arc without a needle. The current
theme's accent applies at every position, including one. Native image semantics
supply a normalized-position or missing-reading summary; applications should
replace it with their scale and units. The gauge is passive and adds no focus stop.

`InstrumentReadout(_:style:)` presents an application-formatted string in theme
accent, with the original string as its accessibility label. `.segmented` is the
default and paints three rows; `.plain` uses native text. Segmented lettering
supports digits, decimal points, colons and signs (`+`, `-`), at most 32 characters.
Empty, unsupported or longer values use native text. Native `ViewThatFits` also
chooses text when the complete lettering does not fit the allocation. Formatting,
units and interpretation remain application-owned; this is a passive readout.
Segmented artwork always measures all three rows, regardless of inherited text
line limits. The ordinary-text fallback retains the caller's native line limit.

## Duration presentation and example-owned timekeeping

`DurationText(elapsed:)` floors whole seconds; `DurationText(remaining:)` rounds
positive fractions up, showing zero only at expiry. Both use `m:ss` below an hour
and `h:mm:ss` thereafter without a 24-hour wrap, accent paint and spoken labels.
Plain text remains the default. `style: .segmented` delegates to
`InstrumentReadout` while retaining duration rounding and spoken labels; its
ordinary-text fallback also applies.
Inputs are nonnegative and at most `Duration.seconds(Int64.max)`, checked before
component extraction. Integer formatting preserves attosecond boundaries.

Applications own measurement, pause/resume, limits and expiry effects; SwiftTUI
owns scheduling/cancellation. The executable's internal immutable `ElapsedTime`
and native timeline demonstrate these contracts. Native schedules retain a stable
origin across renders and pause when idle; recreating a default current-time
origin restarts the driver. No public timekeeping subsystem is part of Chio.

## btop-inspired UI inventory

The accepted btop-inspired work is delivered: a compact palette, optional border
headings, measurement meters and a passive history graph in `--metrics`.
Applications own sampling and interpretation. Dense sorting is demonstrated by
`--inbox`; it does not establish sortable table headers. Draggable split panes,
multiple graph series and additional glyph modes remain unproved. The original
[inventory](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#btop-inspired-ui-inventory)
records the reference audit and extraction rationale.

## Implementation and verification

- [MeasurementGauge.swift](../../Sources/Chio/Instrumentation/Presentation/MeasurementGauge.swift)
- [InstrumentReadout.swift](../../Sources/Chio/Instrumentation/Presentation/InstrumentReadout.swift)
- [Sparkline.swift](../../Sources/Chio/Instrumentation/Presentation/Sparkline.swift)
- [SparklineTests.swift](../../Tests/ChioTests/Instrumentation/Presentation/SparklineTests.swift)
- [DurationTextTests.swift](../../Tests/ChioTests/Instrumentation/Presentation/DurationTextTests.swift)
