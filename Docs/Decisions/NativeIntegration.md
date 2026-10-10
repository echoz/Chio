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
| Cooperative shutdown | Continuous state writes can prolong the final native render drain after quit or EOF. The [upstream proposal](https://github.com/SwiftTUI/swift-tui/pull/45) addresses the drain at its runtime owner. It has not been adopted by Chio; the dependency is unchanged. |
| Portability and accessibility | CI and pseudo-terminals cover specific workflows. Other distributions, architectures, assistive technologies and live SSH devices require separate evidence. Static Linux remains [blocked](Dependencies.md#static-linux-blocker). |

## Cooperative shutdown follow-up

The current direction is an upstream correction, following investigation of
an internal workaround. Retained synthetic regression and process evidence
establishes the native drain issue. The proposal limits cooperative exit to
final-input presentation and required synchronous UI follow-ups, retaining the
acquisition cap. Chio has not adopted the patch; any dependency update still
requires native and Chio integration checks.

At the pinned revision, `onTerminationRequest` runs after the final render drain
for exit keys and batched EOF. Cleanup in that callback alone cannot prevent the
delay. Any workaround must preserve completed final-input presentation, focus and
lifecycle callbacks, termination cancellation, and terminal cleanup. Applications
own their background producers; Chio cannot silently stop arbitrary external work.
A finite acquisition cap does not guarantee a deadline for an arbitrarily
expensive frame or callback.

An application-specific fallback could quiesce producers before an accepted quit:
prevent subsequent background publication, cancel owned producers, then leave
native final-input rendering and cleanup intact. Cancellation alone does not
exclude a queued publication. Preserve focused-control handling and termination
vetoes; observing an exit chord is not proof that the session will end. An
application owning `RunLoop` can also wrap its public input reader to quiesce
before forwarding EOF. The default scene launcher has no public pre-EOF hook.
These requirements make a transparent Chio modifier insufficient. No internal
workaround was implemented or verified as a process fix; upstream correction is
preferred to expanding Chio's application-lifecycle ownership.

Separate startup and task-cancellation delays reproduced on the upstream baseline
and remain unresolved; incremental-rendering performance needs separate measurement.
