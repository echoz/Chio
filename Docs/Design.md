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
| Huh | Bindings, native input controls, submission, focus | Field presentation, validation visibility, form workflow |
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
Native `GroupBox`, `List`, `TextField`, `Picker`, `Toggle`, and `ProgressView`
styles share the same semantic roles. The first appearance closely follows Huh's Charm palette and
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

## Forms and agent creation

The second slice adds a Create agent screen through native `fullScreenCover`.
The dashboard stays mounted underneath, preserving its query, selection, and
native focus for cancellation. The form uses an eager `VStack` in a native
`ScrollView`, with Create and Cancel outside the scroll area. It explicitly
requests Name focus on arrival; native Tab and scroll reveal handle navigation.
Theme and geometry changes update the same view structure and retain draft values.

Chio supplies two small form primitives:

- `FormField` composes a heading, a supplied native control, and a wrapping helper
  or visibly marked error. Errors replace helpers, and semantic theme colors
  determine presentation. Picker/toggle labels remain accessible but are visually
  omitted inside the field to avoid duplicate headings.
- `FormValidation<Field>` records field exits and attempted submission. Apps
  supply their current ordered `Issue` values each time; Chio does not cache
  validation results or own rules. `message(for:in:)` hides errors until blur or
  submission. `submit(_:)` reveals errors and returns the first invalid field for
  an application-owned native focus binding. Hidden fields are excluded by the app.

There is no new form result builder, field registry, or focus manager. The pinned
SwiftTUI has no `Form` declaration; ordinary view composition remains the API.
Chio's compact native picker style displays one value and maps arrow keys to
native selection. It also retains wheel/accessibility selection; it does not
present a pointer option menu. The toggle keeps native Space/Enter activation.

The demo requires a nonblank Name (at most 32 characters). Choosing Test reveals
a required Test suite (at most 40 characters); switching roles retains its draft
but removes its validation while hidden. Outer whitespace is trimmed on creation.
Start immediately defaults on. Create adds one UUID-identified simulated agent,
clears the dashboard filter, and selects it; Cancel adds nothing. Agents exist
only for the current process. Validation prevents submission through both the
form action and the draft-to-agent boundary.

`n` opens from dashboard results; ordinary characters inside the form edit native
controls. Escape cancels, Ctrl-S submits, and Ctrl-T changes theme. Text-field
Return also submits; Return on the toggle keeps native toggle behavior. Duplicate
submit callbacks are guarded by the current presentation state.

SwiftTUI drains input batches before rendering a newly presented cover. During
that handoff, the dashboard guards its shortcuts, carries simple name type-ahead,
maps an initial Tab to a native Role focus request, and handles submission.
Invalid submission reveals errors when the cover arrives; valid submission adds
one agent. The return transition consumes stale events until the updated list
has rendered. Native editing resumes when the cover owns focus. This is a narrow
transition adapter, not general replay of arbitrary navigation across unrendered
controls.

## Source ownership

| Path | Responsibility |
| --- | --- |
| `Sources/Chio/Domain` | Theme values, pure search decisions, and validation visibility |
| `Sources/Chio/Presentation` | Components and environment integration |
| `Sources/Chio/Presentation/Styles` | Native SwiftTUI control styles |
| `Examples/AgentDashboard` | Demo model, presentation, and thin entry point |
| `Tests/ChioTests` | Tests grouped by corresponding responsibility |
| `Tests/ChioDashboardTests` | Simulation, draft rules, and dashboard/form rendering and interaction |

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

Color-depth detection and palette conversion also belong to SwiftTUI. The pinned
ANSI-256 conversion maps dark RGB colors poorly; Chio's default surface becomes
`#5F5F5F` instead of `#211D2A`. True-color SSH sessions should declare
`COLORTERM=truecolor` as documented in the README. Keep the authored palette and
native detection; correcting conversion for limited-color terminals is upstream
work, not a second Chio quantizer or an unconditional true-color override.

- [SwiftTUI style system](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIViews/SwiftTUIViews.docc/Style-System.md)
- [SwiftTUI theme model](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIPrimitives/Styling/Theme.swift)
- [Huh themes](https://github.com/charmbracelet/huh/blob/main/theme.go)
- [Bubbles list](https://github.com/charmbracelet/bubbles/tree/main/list) and [help](https://github.com/charmbracelet/bubbles/tree/main/help)

Charm supplies visual references, not a Go API port. Broader forms, Markdown,
and further products remain deferred while these concrete workflows are refined.
