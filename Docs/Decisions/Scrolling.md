# Native scrolling

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Theme native scroll indicators while retaining native geometry, reveal and event routing.

## Scrolling

`ChioScrollViewStyle` paints idle indicators muted, focused viewports accent, and
focused individual tracks accent only on that axis. Suppression retains muted
paint. Native disabled opacity, glyphs, track space, insets and inherited
background remain intact; the style does not change sizing or cover surfaces.

SwiftTUI owns positions, clipping, input, dragging, reveal and clamping;
`.scrollIndicators(_:axes:)` controls visibility. The style reaches native editor
scroll views, but editor focus is not viewport focus. Lists/Tables have separate
scrolling styles. Native focus reveal includes reserved tracks and can shift the
body offset one cell per overflowing axis. Chio preserves that geometry.

## Implementation and verification

- [ChioScrollViewStyle.swift](../../Sources/Chio/Scrolling/Presentation/ChioScrollViewStyle.swift)
- [ChioScrollViewStyleTests.swift](../../Tests/ChioTests/Scrolling/Presentation/ChioScrollViewStyleTests.swift)
