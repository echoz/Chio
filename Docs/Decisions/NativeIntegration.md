# Native integration boundaries

**Status:** Accepted constraints of the pinned implementation; unresolved limitations remain.

Keep native ownership and visible limitations explicit when composing or extending Chio.

## Native chrome

Native list focus chrome uses SwiftTUI's theme; Chio themes selected content and
controls. The native theme environment is not public. `StatusBar` composes a text
rule because native Divider ignores ambient foreground. Keep these upstream
limits visible without a second focus system or renderer.

## Remaining boundaries

These limits apply to the pinned implementation; none authorizes another
renderer, focus system or hidden dependency patch.

| Boundary | Current limit and responsible follow-up |
| --- | --- |
| Native style hooks | Table border/background chrome, list focus gutter, palette shell, prompt headers and disabled-editor glyph paint are not fully controlled by Chio. Keep native behavior and resolve missing hooks upstream. |
| Layout and lifecycle | Scroll focus reveal can move a two-axis viewport by one cell; nested tab strips can receive stale width proposals; expanded disclosure focus includes descendants. Keep the documented native contracts for [scrolling](Scrolling.md#scrolling), [tabs](Tabs.md#tabs) and [disclosure](DisclosureGroups.md#expandable-groups-and-trees). |
| Choice composition | Changing choice fields inside `GeometryReader` triggered a native debug lifecycle-publication assertion. The full-window example uses `terminalSize`; arbitrary nesting remains unproved. |
| Collection measurement | Native ideal-size probes can realize all rows before a bounded viewport commits and emit deferred `collection.unboundedRealization` warnings. Small fixtures do not prove virtualization or large-dataset performance; diagnostics are retained. |
| Early input | Search, palette and form handoffs cover documented type-ahead/batched paths. Arbitrary multi-control input before presentation settles needs native support, not an application-built editor or focus graph. |
| Cooperative shutdown | Continuous state writes can prolong the final native render drain after quit or EOF. The [upstream proposal](https://github.com/SwiftTUI/swift-tui/pull/45) limits that drain to final-input presentation and required synchronous UI follow-ups. It is not adopted by Chio. |
| Portability and accessibility | CI and pseudo-terminals cover specific workflows. Other distributions, architectures, assistive technologies and live SSH devices require separate evidence. Static Linux remains [blocked](Dependencies.md#static-linux-blocker). |

## Cooperative shutdown follow-up

The upstream proposal preserves completed final-input presentation, cancelled-frame
retries, focus and lifecycle callbacks, terminal cleanup, the existing acquisition
cap and the stricter signal limit. Normal render drains retain their current policy.
The regression and process fixtures use synthetic SwiftTUI-only content.

The proposal does not change Chio's dependency pin or establish consumer adoption.
After upstream review, an explicit dependency update still needs Chio integration
checks and the consuming application's own qualification. A finite acquisition cap
does not guarantee a deadline for an arbitrarily expensive frame or callback.
Separate startup and task-cancellation delays reproduced on the upstream baseline
and remain unresolved; incremental-rendering performance needs separate measurement.
