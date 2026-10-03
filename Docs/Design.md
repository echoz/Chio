# Chio design

Chio provides a coherent terminal appearance and reusable interactions through
SwiftTUI composition. The first slice is an agent dashboard backed by local
simulated data. The contracts below are accepted design; implementation and
validation status live in [the plan](Plan.md).

## Ownership

SwiftTUI owns rendering, terminal lifecycle, layout, state, input, focus, and
scrolling. Chio supplies native control styles and composed views. Reusable UX
justifies a Chio component; renaming an existing primitive does not.

One SwiftPM package exports the `Chio` library and `chio-dashboard` executable.
Application content and layout use SwiftTUI directly. No additional renderer,
state store, or focus manager is part of this design.

## Investigation outcome

| Inspiration | Already provided by SwiftTUI | Chio's useful layer |
| --- | --- | --- |
| Lip Gloss | View layout, padding, borders, colors, style protocols, environment | Semantic tokens and coherent defaults |
| Bubbles | Lists, tables, text editing, scrolling, spinners, progress, command palettes | Search composition, result/empty states, contextual help |
| Huh | Bindings, native input controls, sections, submission, focus | Future validation and form workflow |
| Glamour | Rich text and links as views; no Markdown parser | Future AST-to-view document rendering |
| Charmtone/shared palettes | Color primitives and terminal capability handling | A small semantic palette, not a color catalog |

Use Huh's Charm palette and Bubbles' hierarchy and keyboard help as the initial
visual reference. Go model/update messages, ANSI-string composition, and lipgloss
layout calls do not translate into additional Chio machinery: SwiftTUI already
owns those responsibilities through state, views, and native layout. Native
animations and progress timing remain upstream; the example's cancellable task
only advances simulated application data.

## Theme

A concrete theme value contains nested semantic colors, spacing, and visual
treatments. Chio owns rendering rules; the theme is the primary presentation
customization point and flows through the environment with `.chioTheme(.default)`.
Consumers can copy the default and customize its colors without rebuilding styles.
Component options specify behavior; application composition specifies content.

Changing theme preserves query, stable selection, focus, and entered values.
Native `GroupBox`, `List`, `TextField`, and `ProgressView` styles share the same
semantic roles. The first appearance closely follows Huh's Charm palette and
Bubbles' selected rows, muted metadata, and compact keyboard help.

## Searchable selection

`SearchableList` has an always-visible search field, stable item IDs, optional
external query binding, `.filtering(.fuzzy)`, and an `.onActivate` callback.
Filtering preserves a visible selection; otherwise it selects the first result,
or `nil` if there are no results. Filtering never activates an item.

| Focus | Input | Behavior |
| --- | --- | --- |
| Results | Arrows | Navigate visible results |
| Results | Enter | Activate the selected item |
| Results | `/` | Focus search |
| Results | Escape | Clear the filter |
| Search | Text | Filter immediately |
| Search | Enter | Focus results and retain the query |
| Search | Escape | Clear the query and focus results |
| Either | Tab | Use native focus navigation |

Application shortcuts must not consume ordinary text while editing search.
Selection and keyboard focus are distinct. Empty source data and a search with
no matches have separate messages.

The persistent `›` marker represents selection. SwiftTUI's native `▌` and row
chrome show keyboard focus, which Tab can move without changing selection.
Enter is scoped to results and activates the reconciled selected ID. Arrow keys
retain native navigation from the focused row. Rows contain passive presentation;
place buttons and editors outside the searchable list.

Attach application shortcuts with `.onResultKeyPress(perform:)`. The
`.onSearchFocusChange` callback is for presentation such as contextual hints;
its render-driven updates must not guard an ancestor's input routing.

## Composition and layout

`KeyHint` renders one shortcut and explanation; `KeyHints` composes contextual
help. `StatusBar` presents compact application status. The dashboard combines
these with searchable agents, details, and native progress.

Narrow terminals must retain usable search and selection, readable status, and
essential shortcuts. Resize and theme switching should preserve interaction state.
The demo exposes successful and failed simulated runs and empty results without
network calls, credentials, or external service setup.

At widths below 88 cells the dashboard stacks its sections; below 26 rows it
prioritizes the list and essential shortcuts. The full layout is intended for
100 × 30 or larger, with a usable compact layout at 36 × 18.

## Source ownership

| Path | Responsibility |
| --- | --- |
| `Sources/Chio/Domain` | Theme values and pure search decisions |
| `Sources/Chio/Presentation` | Components and environment integration |
| `Sources/Chio/Presentation/Styles` | Native SwiftTUI control styles |
| `Examples/AgentDashboard` | Demo model, presentation, and thin entry point |
| `Tests/ChioTests` | Tests grouped by corresponding responsibility |
| `Tests/ChioDashboardTests` | Simulation and complete dashboard rendering |

Only create responsibility groups when they contain useful code. Keep each
independently useful production type in a matching file and protocol conformances
in dedicated extensions, following the project working agreements.

## References and boundaries

The dependency is pinned because SwiftTUI is still evolving. Its published
`SwiftTUIViews` product is the library boundary; the demo uses `SwiftTUI`, and
tests use public `SwiftTUIRuntime` rendering and hosted input APIs. Chio adds no
external dependency beyond SwiftTUI and does not use testing SPI.

Native list focus chrome currently resolves through SwiftTUI's own theme;
Chio's selected row, content, controls, and hints use the Chio theme. Upstream
does not expose its theme environment publicly, so exact customization of the
native focus gutter remains an integration gap. Do not hide this with a second
focus system or a private API dependency. `StatusBar` uses a composed text rule
because the pinned native `Divider` does not honor ambient foreground styling.

- [SwiftTUI style system](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIViews/SwiftTUIViews.docc/Style-System.md)
- [SwiftTUI theme model](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIPrimitives/Styling/Theme.swift)
- [Huh themes](https://github.com/charmbracelet/huh/blob/main/theme.go)
- [Bubbles list](https://github.com/charmbracelet/bubbles/tree/main/list) and [help](https://github.com/charmbracelet/bubbles/tree/main/help)

Charm supplies visual references, not a Go API port. Forms, Markdown, and further
products remain deferred until the first slice demonstrates the design.
