# Confirmation and transient feedback

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Style native confirmation, activity and transient feedback while preserving native presentation lifetimes.

## Confirmation and transient feedback

`ChioPromptStyle` supplies bounded compact alert/confirmation surfaces, message
viewport, accent border and strokes. Bordered prompts reserve at least one vertical
cell for the overlay border. Native header tone/placement, title/close button,
modal focus, Escape, restoration and dismissal remain upstream; arbitrary header
background colors are not exposed.

Apps author action content and explicitly clear presentation on custom actions.
Roles describe/style actions; Escape/close dismiss without invoking a Cancel
closure. Shared dismissal effects belong in `onDismiss`. Direct actions form a
horizontal row; apps can supply a VStack, since styles cannot reorder/wrap arbitrary
content. Presentation bindings retain projected state before deferred authoring.

`ChioSpinnerStyle` keeps native braille cadence, ticking/cancellation, accessibility
and reduced-motion first frame, with muted/accent/success phases. Explicit
`ChioToastStyle(theme:tone:)` uses native `TerminalTone`; there is no environment
toast modifier. Native stacking/expiry/dismissal retain underlying editing focus.
Toasts can cover bottom content and do not constitute a persistent status queue.
Application tasks own simulated work and cancellation; native controls own timing.

## Implementation and verification

- [ChioPromptStyle.swift](../../Sources/Chio/Presentation/Styles/ChioPromptStyle.swift)
- [ChioPromptStyleTests.swift](../../Tests/ChioTests/Presentation/ChioPromptStyleTests.swift)
- [FeedbackExampleTests.swift](../../Tests/ChioDashboardTests/Presentation/FeedbackExampleTests.swift)
