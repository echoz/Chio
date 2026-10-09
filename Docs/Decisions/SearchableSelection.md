# Searchable selection and membership

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Compose search with native lists, keeping selection, membership and keyboard focus distinct.

## Searchable selection

`SearchableList` combines an always-visible native search field, stable item IDs,
optional external query binding, fuzzy/substring filtering and activation.
Filtering preserves a visible selection, otherwise chooses the first result or
`nil`. It never activates. Query edits reconcile selection before another control
can act, using the query retained by the binding even when writes are rejected or
transformed. External query/data changes also reconcile during rendering.

| Focus | Input | Behavior |
| --- | --- | --- |
| Results | Arrows / Enter | Native row navigation / activate selected ID |
| Results | `/` / Escape | Focus search / clear filter |
| Search | Text / Enter | Filter immediately / retain query and focus results |
| Search | Escape | Clear query and focus results |
| Either | Tab | Native focus navigation |

Selection and focus differ: persistent `›` marks selection; native `▌`/row chrome
marks keyboard focus, which Tab may move independently. Enter activates the
reconciled selection; arrows navigate from the focused row. Empty source data and
no matches have distinct messages. When Return has requested results focus, a
second Return activates the current filtered selection even during the native
handoff; no matches remain inert. Slash-to-search carries simple type-ahead.

Rows contain passive presentation; place editors/buttons outside them. Scope
application shortcuts through `.onResultKeyPress(perform:)` so ordinary search
text reaches the editor. `.onSearchFocusChange` is render-driven presentation
feedback and must not gate ancestor input routing.

## Searchable multiple choice

`SearchableChecklist` uses the matcher, native List set selection and explicit
checkmarks. The binding contains checked stable IDs; native focus is an independent
cursor. Filtering never changes membership. Fuzzy is default; substring filtering
and external query bindings are supported. Counts include hidden/unavailable checks.

Only visible, enabled IDs may toggle. Disabled choices stay visible native focus
stops with an Unavailable label; both toggle directions are rejected. Removed
checked IDs remain bound and count as unavailable. Source/query/theme/geometry
changes never prune or auto-select IDs. Applications own membership validity,
limits, removal and reset policy.

A binding adapter gates native membership changes against current visible/enabled
IDs, preserving all others. It reads authoritative query and membership at
dispatch; paint/counts use the value the application retained after any transformed
or rejected write. Source items and eligibility update with rendered views; the
gate provides no freshness guarantee for source changes not yet rendered. There
is no parallel selection store.

Search starts focused. Return requests a List-only native focus namespace; arrows
move the cursor and Space/Return toggle through the same gate as native activation.
Native scrolling owns reveal. Stable membership does not promise stable item focus
through arbitrary reordering: native row indices can change. `/` enters search;
Escape clears it and returns to rows when results exist. No-result Return keeps
editing focus. Unmodified input during search-to-results handoff is consumed until
focus arrives, preventing stale-row toggles. Results shortcuts use the same scoped
callback as `SearchableList`.

## Implementation and verification

- [SearchableList.swift](../../Sources/Chio/Presentation/SearchableList.swift)
- [SearchableChecklist.swift](../../Sources/Chio/Presentation/SearchableChecklist.swift)
- [SearchableListTests.swift](../../Tests/ChioTests/Presentation/SearchableListTests.swift)
- [SearchableChecklistTests.swift](../../Tests/ChioTests/Presentation/SearchableChecklistTests.swift)
