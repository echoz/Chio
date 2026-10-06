# Chio design

Chio is an opinionated, declarative presentation and interaction layer over
SwiftTUI: “Beautiful terminal interfaces for Swift.” These are the accepted
architecture and interaction contracts for the experimental source release.
[Plan.md](Plan.md) owns delivered scope, verification and remaining work;
[Examples.md](Examples.md) owns commands and workflows; [Usage.md](Usage.md)
owns public API recipes. Historical implementation decisions and evidence remain
in [the v0.1.0 documents](https://github.com/echoz/Chio/tree/v0.1.0/Docs).

## Ownership

SwiftTUI owns rendering, terminal lifecycle, layout, state, input, focus,
scrolling, scheduling and native presentation. Chio supplies semantic themes,
native control styles and composed views. One SwiftPM package exports the `Chio`
library and `chio-dashboard` executable; applications compose SwiftTUI directly.

A public addition must provide reusable presentation or interaction: readability,
focus/selection feedback, filtering, editing or navigation. Renaming a primitive
or making an example model immutable does not justify a library component.
Applications own clocks, monitoring, sorting policy, validation rules, review
state, persistence and external operations. Extract shared UI behavior only when
composition demonstrates a concrete missing contract. Showcase applications
validate the framework; their domain models do not define its product scope.
Coverage inventories describe gaps, without committing to catalog parity.

## Value contracts

Owned domain values and view configuration have `let` stored properties and pure
computed observations. Transformations return replacements and leave inputs
unchanged; local scratch mutation is permitted. Explicit mutable boundaries are
SwiftTUI state/binding/focus/namespace/environment wrappers, ArgumentParser command
options, filesystem resource owners, and live test-session recorders with frames,
continuations and deadlines.

Prefer synthesized `Hashable`, `Codable` and `Sendable` where their contracts fit.
Enforce restricted-value invariants through construction, replacement and decoding;
malformed decoding must reject through the same validation as construction.
Validation flags cannot replace invariants or contextual runtime checks. Draft
bindings read current retained storage before replacing a field, preserving other
fields even when multiple input events arrive before a frame.

Field descriptions and shortcut details are nonoptional strings: empty means no
supporting row. Shortcut decoding accepts historical missing/null detail as empty;
encoding always includes a string, and missing/empty details compare equally.
Errors retain meaningful optional presence: a present empty error still suppresses
help. Selection and native state ownership retain meaningful absence. Omitted
replacement arguments preserve values; supplied empty values clear them. Markdown
normalizes missing language/destination text at parsing. Search callbacks have
neutral defaults; modifier copies retain callbacks and native state identity.

Native `StrokeStyle` is only `Equatable` and `Sendable`, including inaccessible
state. `ChioTheme` and `Treatments` retain those conformances; `Colors`,
`SyntaxColors` and `Spacing` also support hashing and coding. Do not clone strokes
or add lossy coding to gain conformance. Parsed Markdown and report/presentation
snapshots are immutable, hashable and sendable without a persistence schema:
native table alignment is not Codable, and reconstructing a report from its agent
would lose the captured document. Process-relative example timekeeping likewise
has no persistence representation.

Incomplete agent drafts are valid editable values; checked creation enforces form
rules. Running progress is a checked finite fraction in `0..<1`; completion is a
separate phase. Simulation takes its step explicitly and returns replacement agents.

## Investigation outcome

| Reference | Native foundation | Chio contribution |
| --- | --- | --- |
| Lip Gloss / Charmtone | Layout, borders, colors, environment | Semantic palette and coherent defaults |
| Bubbles | Lists, tables, editing, scrolling, progress, palettes | Search composition, empty states and contextual help |
| Huh | Bindings, controls, submission, focus | Field presentation and validation visibility |
| Glamour | Rich text and links | Parsed Markdown composed into themed native views |
| btop | Canvas, groups, progress and authored layout | Compact styles and passive history presentation |
| gh-dash / Hunk | Lists, previews and ID-based scroll reveal | Example inbox composition and bounded diff proof |

Charm supplies visual references, not a Go API port or ANSI-string/layout engine.
Huh's Charm palette and Bubbles' hierarchy/help inform the default appearance.
btop informs compact instrumentation; gh-dash and Hunk inform review composition.
GitHub/VCS operations, authentication, file watching and agent protocols remain
application work. These examples do not establish product parity.

## Theme

`ChioTheme` contains semantic colors, syntax colors, spacing and treatments;
`.chioTheme(...)` applies it through the environment and installs native styles.
Use `replacing(...)` on the theme and nested values to customize presentation.
Construction and replacement preserve nonnegative spacing and printable
single-cell glyph preconditions. Options own component behavior; application
composition owns content and layout.

The default, light and btop presets share the same interaction policy. The
executable's `ExampleTheme` is an internal comparison choice, not a public theme
registry or restriction on custom values. Theme changes preserve query, stable
selection, focus, entered values and relevant native scroll positions.

Native groups, lists, tables, buttons, links, text fields/editors, pickers, toggles,
tabs, scroll/disclosure views, progress, spinners and prompts share semantic roles.
Bordered buttons inherit their surface and use an accent outline for focus/enabled
press, or error for destructive actions. Idle borders use the ordinary border
color; disabled controls retain native dimming. Focus-effect suppression removes
the focused outline. Authored labels remain native content. Outlines avoid a
whole-cell rectangular fill behind rounded border glyphs.

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

## Composition and layout

`KeyHint` renders one description, `KeyHints` wraps compact hints, and `StatusBar`
presents application status. Narrow layouts retain usable search/selection,
readable status, errors/actions and essential hints. Resize/theme changes preserve
interaction state. Keep state above alternative layouts: native `ViewThatFits`
resolves all alternatives.

The dashboard stacks below 88 columns and prioritizes list/essential hints below
26 rows. Its full layout targets 100 × 30 or larger; 36 × 18 is the compact target.
Local examples demonstrate successful/failed runs and empty results without
external services. Their fixture sizes do not establish large-data behavior.

## Duration presentation and example-owned timekeeping

`DurationText(elapsed:)` floors whole seconds; `DurationText(remaining:)` rounds
positive fractions up, showing zero only at expiry. Both use `m:ss` below an hour
and `h:mm:ss` thereafter without a 24-hour wrap, accent paint and spoken labels.
Inputs are nonnegative and at most `Duration.seconds(Int64.max)`, checked before
component extraction. Integer formatting preserves attosecond boundaries.

Applications own measurement, pause/resume, limits and expiry effects; SwiftTUI
owns scheduling/cancellation. The executable's internal immutable `ElapsedTime`
and native timeline demonstrate these contracts. Native schedules retain a stable
origin across renders and pause when idle; recreating a default current-time
origin restarts the driver. No public timekeeping subsystem is part of Chio.

## Contextual keyboard help

Immutable `ShortcutHint` values contain authored key/action/detail text;
`ShortcutGroup` preserves title, order and duplicates. Both are Codable, Hashable
and Sendable. Empty details/groups are omitted; all-empty help has an explicit
message. Descriptions neither register actions nor parse key labels into input.
The pinned command registry and `KeyBinding` are not public.

`KeyHint`/`KeyHints` share those values with grouped, wrapping `KeyboardHelp`.
Applications derive descriptions from context/availability; native handlers remain
execution authority. Help is passive content for inline or native presentation.
A full-screen help reader retains the background subtree for native focus
restoration. Cover-wide handlers reach both controls and viewport; handlers inside
sheet content cannot reach its outer header/viewport.

Printable help shortcuts are scoped outside editors. A retained help context
survives modal focus changes; a context-independent reference avoids pending-focus
ambiguity. Pending presentation blocks background actions and consumes immediate
Escape, including input arriving before the next frame.

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

## Pagination

`Pagination` models finite nonnegative count, positive size and zero-based current
page, nil exactly when empty. Construction/replacement check preconditions;
malformed decoding throws. The value is Hashable, Codable and Sendable. Page counts
and ranges use constant-time arithmetic through `Int.max`, without page arrays.

`selectingPage(at:)` returns nil for invalid indices. First/previous/next/last
transitions clamp at boundaries. `updatingTotalCount(to:)` preserves a valid page
or clamps to the last; `resizingPages(to:)` retains the old first visible item in
the new page. Empty-to-nonempty starts at page one; explicit construction starts
a new result set. Applications own count/query changes and loading policy.

`PageControl` binds the complete value, composing native Previous/Next buttons and
page/item-range summaries. Empty/single-page actions are disabled. Arrows/Home/End
are scoped to buttons. Actions reread retained bindings; rejected/transformed
writes create no local optimistic cursor. Native focus, pointer input and layout
remain authoritative. Async paging, unknown totals and cross-page item selection
are outside this finite-value contract.

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

## Command palette

`ChioPaletteStyle` styles native `paletteSheet`; apply the theme outside the
declaration. Applications register actions through native `Panel`, `keyCommand`
and `paletteCommand`, without a Chio registry or coordinator.

Fuzzy filtering preserves stable command IDs. The native editor keeps editing
focus while arrows/Tab move selection; Return activates natively and Escape
dismisses. Disabled commands remain visible/inert; unmatched queries show feedback.
A bounded window reveals selection; short terminals omit descriptions but retain
names/help. `initialQuery` seeds each opening. Resolved editor bindings prevent
reopening from activating earlier-lifetime state.

The dashboard queues an action until native presentation becomes false, allowing
focus restoration before launching a form/report. Replacing palette with cover in
the same frame would capture departing palette focus. Opening batches may precede
the first palette frame: a bounded adapter carries simple text/backspace and
Escape, consuming navigation/Return and blocking background shortcuts until native
focus arrives. This is not general event replay. Dropdown surface/divider remain
native chrome; pinned `sheetStyle` cannot style that container.

## Forms and agent creation

`FormField` composes a heading, supplied native control and wrapping help/error.
Errors replace help and carry a visible marker. Picker/toggle labels stay
accessible while visually omitted inside fields to avoid duplicate headings.
`FormValidation<Field>` records exits/submission, not rules or cached results.
Applications supply current ordered issues: `message(for:in:)` hides errors until
blur/submission; `recordingExit(from:)` returns visibility; `submitting(_:)` returns
visibility and first invalid field for native focus. Apps exclude hidden fields.

Native controls/bindings/focus own editing. The compact picker maps arrows and
wheel/accessibility to selection without a pointer option menu; toggles retain
Space/Return. Ordinary composition is the form API; the pin has no `Form` declaration.
Keep persistent drafts above responsive layouts. Read current storage in binding
setters, validate current drafts before committing snapshots, and reveal the first
invalid heading/error with native scroll readers. Cancel restores accepted values
and visibility; restoration is not an exit from the abandoned field.

Agent creation uses a retained dashboard beneath a native full-screen cover,
scrolling fields with actions outside, and explicit initial Name focus. Names
must be nonblank and at most 32 characters; Test reveals a required suite of at
most 40. Hidden suite drafts remain retained but unvalidated. Creation trims outer
whitespace, adds one UUID-identified process-local agent, clears filtering and
selects it; Cancel adds nothing. Both submission and checked creation validate.
Duplicate submits are guarded by current presentation state.

During pre-frame cover handoff, dashboard shortcuts are blocked; simple name
text, initial Tab focus and submission are adapted narrowly. Invalid submission
reveals errors on arrival; valid submission creates once. The return transition
consumes stale events until the updated list renders. Native editing resumes with cover focus.
Forms/checklist/settings examples keep rules, save/cancel and drafts application-owned;
there is no form DSL, field registry, scheduler or persistence subsystem.

## Password and multiline input

Native `SecureField` uses `ChioTextFieldStyle`. SwiftTUI masks before styling and
withholds secure values/text-query metadata from public semantic snapshots.
Authored labels/help/feedback must never interpolate passwords. Mask/reveal
controls are not public options; Chio adds no credential model.

`ChioTextEditorStyle` places protected `editorContent` once with surface, inset,
border and focused accent. Native binding, cursor, selection, wrapping, paste,
viewport and one focus stop remain intact. Applications bound height. Tab leaves;
Return inserts a newline; Home/End navigate the logical line. Secure-field Return
uses native submission when supplied.

Enabled editor text samples the surrounding foreground before styling;
`.chioTheme` supplies both foreground and frame style. A standalone style cannot
retroactively change sampled text paint. Disabled text keeps native placeholder
paint/dimming without an extra opacity layer or replacement editing content.
The local example clears passwords on Save/Cancel and never authenticates,
transports or persists them.

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

## File selection

`FilePicker` chooses one existing readable regular file through native searchable
selection plus directory loading/navigation, eligibility, errors/retry and explicit
confirmation. Browsing/filtering/cancel preserve the committed URL. Confirmation
commits only after checks; rejected binding writes keep the picker open with
feedback. Confirm/cancel makes the picker inactive; dismiss/recreate for another choice.

The start directory is not confinement. Inputs are absolute local file URLs;
dot components normalize lexically and Parent stops at `/`. File/directory
symlinks are followed outside the starting directory; display/returned paths retain
the chosen symlink route. Broken links, unreadable/special files cannot confirm.
Directories sort first, then case-insensitive names with deterministic ties.
Dot/filesystem-hidden entries require opt-in visibility.

`FileExtensionFilter.all` allows regular files; `.only([])` allows none;
`.only([""])` includes extensionless files. Matching uses the chosen filename's
extension case-insensitively without a leading dot. Authored sets are not trimmed
or repaired; directories stay navigable. Search is current-folder-only. Changed
start-directory/hidden policy reloads; theme/geometry preserve folder/filter.

An internal actor owns Foundation metadata/enumeration off the main actor, retained
through native state. Native `.task(id:)` cancels work. Every load/confirmation has
a fresh generation; completion checks cancellation before reading the captured
state binding and rejects stale generations. Navigation, confirmation-time editing,
cancel/disappearance invalidate work. Blocking calls may finish after cancellation,
but cannot commit cancelled results.

Confirmation rechecks current kind/readability without opening/reading contents,
reserving an inode or guaranteeing a later application open. The example reads
local listings without modifying files. Plain snapshots cannot await loading and
are rejected rather than pretending to contain a loaded listing.

## Dense review inbox

The executable composes native Pickers, `SearchableList`, passive Markdown preview
and full-screen reading over sixteen fixed local review snapshots. Application
queue membership/sorting precede substring filtering; stable IDs preserve selection
through sorting. Queue changes immediately exclude invalid selection; activation
rechecks current membership before opening. Empty matches cannot preview/activate.

One mounted list retains its modifier chain while the optional sibling preview
appears at 88 × 26 or larger. The queue takes roughly two fifths of pane width with
a 40-column minimum; a two-cell gap separates preview. Without preview the queue
fills width. Preview is passive; full reading works at every size, and resize does
not dismiss it. Covers and pending presentation consume background queue actions;
ordinary printable input remains search text.

Opening first requests results focus, then native `onChange` presents after the
background frame commits focus. Escape cancels either phase; the callback reads
current phase to avoid reopening. This depends on pinned focus-before-lifecycle
ordering, without timers/yields or another focus system. A selected snapshot
composes the original `ReviewItem` and parsed document until the ID changes.
Fixtures remain Codable; derived snapshots follow the Markdown exception. No public
inbox, sorter, master/detail or review coordinator is implied.

## Read-only diff prototype

Executable-only `DiffFile`/views provide a bounded proof, without public Chio API
or dependency. Immutable changes distinguish modified/added/deleted/renamed paths;
binary content differs from textual hunks, including empty textual files.

Zero-based hunk offsets and context/change blocks are checked on construction and
decoding: reject negative/overflowing ranges, multiline source entries, empty
changes, overlap and inconsistent unchanged gaps. Complete normalized file diffs
require equal omitted old/new prefixes/gaps; partial hunks need another contract.
Counts/numbers/unified/split rows derive from blocks. Missing split cells differ
from present empty source lines; replacement lines pair in order with excess
retained on their own side.

One native two-axis scroll owner aligns split panes. Literal native Text and public
cell measurement retain source; markers/ink distinguish changes independently of
success/error status. Below 92 columns presentation is unified; widening restores
requested layout. Native anchors reveal a retained logical hunk after navigation,
file changes/relayout. Manual scrolling does not change that explicit target;
theme preserves offset. Palette policy remains example-local.

Lines are unwrapped because native word wrapping can remove boundary whitespace
and add continuation marks. Wrapped source requires a faithful native contract.
Long lines widen split panes and require horizontal navigation. Tabs/Unicode use
native measurement, without editor tab-stop/terminal agreement guarantees. The
eager small-fixture reader is not virtualized or certified for large patches.
There is no diff parser, VCS adapter, repository/review/annotation subsystem.

## Markdown and agent reports

`MarkdownDocument(source)` parses once into an immutable Hashable/Sendable value;
applications retain it until content changes. Third-party AST/parser types remain
internal. `MarkdownView` consumes the document/theme; apps supply vertical scrolling.
Native views compose headings, rich paragraphs, emphasis, code, lists/tasks,
quotes, rules and tables. Each paragraph is one rich Text with native span wrapping.
Smart punctuation is disabled. Quotes use a text marker because pinned leading-edge
borders disappear on one-row content. Images show alt/source; HTML stays literal.

Fenced code preserves parsed whitespace in a native horizontal scroll view.
Swift-only highlighting is automatic: first whitespace-delimited fence word,
case-insensitive `swift`. Tree-sitter parses during document construction and stores
private immutable semantic ranges beside authoritative text. Grapheme-aligned
source slices feed native rich Text without formatting/reconstruction. Unknown,
unlabeled, unsafe-range or oversized (>65,536 UTF-8 bytes) code stays wholly plain.
A deterministic 4,096-progress-checkpoint budget falls back to plain without clock
reads; scanner operations are outside callbacks, so this is not a wall-time/memory
bound. An iterative C cursor classifies roles; strings/interpolation share string
paint. Partial/malformed grammar recognition always retains literal source.

Equality/hash use code language/text with Swift canonical Unicode semantics;
derived ranges do not define identity or require bytewise-equal spellings.
`ChioTheme.syntax` supplies keyword/type/string/number/comment colors, independent
of status roles; ordinary foreground handles identifiers/punctuation/operators.
`.codeHighlighting(.plain)` suppresses paint; `.automatic` is default. Modifiers
retain installed link actions, native scroll identity and ranges. Syntax colors
are separate from the existing Codable `Colors` schema.

Whitespace means parsed Markdown text: cmark normalizes CRLF to LF; blank rows
and parsed trailing newline remain. Native tabs measure one cell and Unicode
width is approximate. Highlighting preserves those semantics, adding no renderer.

Tables retain cells/native alignments and compose native Table/TableRow, with
horizontal scrolling for readable narrow-screen columns. Body cells retain rich
styling; native headers accept uniform plain labels. Tables are eager, not large
data grids. `ChioTableStyle` supplies semantic headers/rounded borders, but native
chrome masks border/background paint. Public row backgrounds preserve Markdown
body contrast; no replacement table conceals the upstream limitation.

The existing initializer keeps links passive with readable destinations. Explicit
`MarkdownView(document, openLink: OpenLinkAction { ... })` opts into native links;
false never falls back to the system opener. Applications own schemes, relative
paths, fragments, external effects and feedback. Parsed `LinkDestination` is not
rewritten; Chio does not resolve/fetch/open it. Document identity preserves link
structure, distinct from text resembling passive fallback; no persisted schema exists.

Each link has one complete rich label/native focus stop; adjacent links stay
separate even with equal destinations. Empty destinations stay passive; empty labels
with destinations show them. Table body links activate; headers stay readable
plain labels/destinations. `ChioLinkStyle` accents/underlines enabled links, adds
bold/selected surface for focus/press, and dims disabled links whose native input
is inert. Suppression removes focus paint while retaining activation. Link paint
wins over inline code for visible focus, preserving authored strong/emphasis.
Native wrapping/hit regions, traversal and scroll reveal remain authoritative.

Reports capture current agent and parsed document once; underlying simulation does
not rewrite the reader. Reopening captures latest state. User-authored metadata is
escaped as literal Markdown; content identifies local simulation. Native covers
retain background query/selection/focus, focus the reader on arrival and restore
on close. Header/hints stay outside scrolling even at 36 × 18. Pending cover input
blocks background shortcuts so batched activation cannot accidentally quit.

## Source ownership

| Path | Responsibility |
| --- | --- |
| `Sources/Chio/Domain` | Theme/shortcut values, pure search/membership, pagination, validation visibility, file observations and parsed Markdown |
| `Sources/Chio/Execution` | Filesystem loading/confirmation checks |
| `Sources/Chio/Presentation` | Components/environment integration; `Styles` owns native styles |
| `Examples/AgentDashboard` | Local models, workflows/views and thin entry point |
| `Tests/ChioTests`, `Tests/ChioDashboardTests` | Library responsibilities and example domain/hosted interactions |
| `Docs/Site`, `Docs/Media`, `Scripts/docs` | Static showcase, shared terminal assets and assembly without Swift build |

Create only useful responsibility groups; independently useful production types
have matching files and dedicated conformance extensions. Private nested helpers
retain inline conformances when extraction would widen access; raw enums keep
language-required placement. Shared frame recorders live in target `TestSupport`;
scenario fixtures/expectations remain beside suites. Global engineering/layout
rules remain in the working agreements rather than being duplicated here.

## References and boundaries

The library uses published `SwiftTUIViews`; the executable uses `SwiftTUI` and tests
use public `SwiftTUIRuntime` raster/hosted APIs, without testing SPI or private APIs.
All four direct dependencies are revision-pinned:

| Dependency | Pin and reason |
| --- | --- |
| SwiftTUI | `2d84ac7083993da2ef52e9d3d30255467efb9553`; inspected evolving beta API |
| Swift Markdown 0.9.0 | `25cb61d3482054b09ae76ca4f281b1bfe7fe5a43`; revision permits conditional Windows unsafe flags |
| Tree-sitter 0.26.13 | `d97971e24500218865c05ed1febdee2acf41bae1`; last release with upstream SwiftPM manifest |
| tree-sitter-swift 0.7.4 | `82bb3a533e0801fd2bbaa11dc49676e10bf41948`; generated C grammar |

Version-based Chio requirements (`from:` or `exact:`) cannot resolve this
revision-pinned graph. Consumers of the experimental v0.1.0 source release pin
Chio's immutable revision `1bcc08ce23747c8c8b1121e3add3c37951f7b09e`.
Swift Markdown brings swift-cmark 0.9.0 built from source, without a separately
installed library. Tree-sitter/Swift grammar are MIT-licensed C targets requiring
neither a Swift wrapper nor grammar generation. The grammar copies unused queries;
Chio does no query-resource I/O and generates no Objective-C/Foundation accessor.
Build cost, portability evidence and remaining musl blockers belong in Plan.md;
ordinary glibc support does not establish static-musl distribution.

Native list focus chrome uses SwiftTUI's theme; Chio themes selected content and
controls. The native theme environment is not public. `StatusBar` composes a text
rule because native Divider ignores ambient foreground. Keep these upstream
limits visible without a second focus system or renderer.

SwiftTUI owns color-depth detection/conversion. The pin reads environment variables,
without true-color query/terminfo: missing `COLORTERM` selects ANSI256 for
`xterm-256color` and ANSI16 for `xterm-ghostty`, neither proving capability. Its
ANSI256 conversion poorly maps dark RGB; default surface maps to `#5F5F5F` instead
of `#211D2A`. True-color SSH sessions declare metadata as described in
[Examples.md](Examples.md#colors-over-ssh). Applications own explicit capability
policy; Chio keeps authored palettes/native detection. The historical conversion
patch is shelved, absent from the pin, and does not fix discovery.

- [SwiftTUI style system](https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/SwiftTUIViews.docc/Style-System.md)
- [SwiftTUI theme model](https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIPrimitives/Styling/Theme.swift)
- [Huh themes](https://github.com/charmbracelet/huh/blob/main/theme.go)
- [Bubbles list](https://github.com/charmbracelet/bubbles/tree/main/list) and [help](https://github.com/charmbracelet/bubbles/tree/main/help)
