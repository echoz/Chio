# Native tabs

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Style native tabs while preserving their selection, overflow and content-lifecycle contracts.

## Tabs

`ChioTabViewStyle` styles native `TabView`/`Tab`: a two-row strip uses accent text
and a persistent rule for selection, surface fill for focus. Suppression removes
focus fill while retaining selection. Native titles/details/badges use cell
measurement; narrow strips place trailing options in More. Disabled state is native.

SwiftTUI owns binding, cursor, routes and content lifecycle. Left/Right/Home/End
move the strip cursor; Return/Space activate; Down opens overflow; Up/Down move
there; Escape closes it; Tab/Shift-Tab leave. Chio adds no replacement handlers.
The menu's native scroll offset derives from the raw cursor even with suppressed
focus paint; wheel offset is not persistent. Overlay geometry bounds paint to the
allocated view without wrapping content. Below three columns or five rows, the
bordered menu is omitted; content also needs sufficient space.

An unconstrained HStack followed by `.frame(width:)` can allocate less width than
SwiftTUI published for overflow partitioning. Native clipping limits paint, but
neither repartitions options nor clips hit regions; pointer routes can extend
beyond the visible strip. Keyboard routing still follows native tags. Arbitrary
nested-layout behavior remains an upstream boundary.

Stable tab values retain dormant value state; removing tabs/replacing owning
identity resets it. This does not promise live resource/task retention. Invalid
selection uses the first live tab without rewriting the binding. Empty tabs are
an inert native focus target; no per-option disabled API exists. Overflow needs a
fresh native menu frame before subsequent navigation; Chio does not replay input.

## Implementation and verification

- [ChioTabViewStyle.swift](../../Sources/Chio/Presentation/Styles/ChioTabViewStyle.swift)
- [ChioTabViewStyleTests.swift](../../Tests/ChioTests/Presentation/ChioTabViewStyleTests.swift)
