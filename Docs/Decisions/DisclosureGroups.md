# Expandable groups and trees

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Style native disclosure groups without introducing another tree or focus model.

## Expandable groups and trees

`ChioDisclosureGroupStyle` composes a focus rail, expansion triangle and authored
label. Expanded triangles are accent, collapsed muted. Focus/enabled press uses
the selected surface; idle inherits background; suppression removes highlight;
disabled headers retain native dimming. Content is placed once, indented four
cells. Direct children form a column; authored stacks keep their layout.

The native trigger wraps only the header. SwiftTUI owns expansion bindings,
activation, accessibility and focus: Return/Space toggles; Tab and arrows retain
native navigation. Values surviving collapse belong outside omitted child content.
Native focus reveal can consider the whole expanded branch. `OutlineGroup` remains
a separate always-expanded native outline, not a replacement tree model.

The example owns stable branch IDs and expansion choices. Parent collapse retains
child choices; explicit Collapse all clears them, including hidden descendants.
Files are passive labels and empty branches have feedback. No filesystem tree API
is implied.

## Implementation and verification

- [ChioDisclosureGroupStyle.swift](../../Sources/Chio/Composition/Presentation/ChioDisclosureGroupStyle.swift)
- [ChioDisclosureGroupStyleTests.swift](../../Tests/ChioTests/Composition/Presentation/ChioDisclosureGroupStyleTests.swift)
