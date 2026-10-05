# Chio design

Chio provides a coherent terminal appearance and reusable interactions through
SwiftTUI composition. The first slice is an agent dashboard backed by local
simulated data. The contracts below are accepted design; implementation and
validation status live in [the plan](Plan.md).

Completing a vertical slice demonstrates a particular end-to-end workflow. It
does not establish broad component coverage or equivalence with Bubbles, Huh,
or Glamour. The [coverage map](Plan.md#component-coverage) distinguishes shipped
Chio behavior, native SwiftTUI capabilities, and remaining product work.

## Ownership

SwiftTUI owns rendering, terminal lifecycle, layout, state, input, focus, and
scrolling. Chio supplies native control styles and composed views. Reusable UX
justifies a Chio component; renaming an existing primitive does not.

One SwiftPM package exports the `Chio` library and `chio-dashboard` executable.
Application content and layout use SwiftTUI directly. No additional renderer,
state store, or focus manager is part of this design.

## Value contracts

Owned domain values and view configuration have `let` stored properties and pure
computed observations. Transformations return new values and leave their inputs
unchanged. Local scratch variables are permitted. SwiftTUI's state, binding,
focus, namespace, and environment wrappers remain native mutable boundaries;
ArgumentParser owns command-option mutation. Live test-session recorders own
mutable frames, continuations, and deadlines. These are explicit state/resource
owners, not immutable domain values.

Prefer synthesized `Hashable`, `Codable`, and `Sendable` for domain values. Check
invariants in every construction, replacement, and decoding path. Decoding a
restricted value must reject malformed input through the same validation as its
ordinary constructor; successful round trips alone do not prove this guarantee.
No validating flags substitute for the value's actual invariants or runtime checks.

Native `StrokeStyle` is only `Equatable` and `Sendable` in the pinned dependency,
including state Chio cannot access. `ChioTheme` and `Treatments` retain those
conformances; Colors and Spacing also support hashing and coding. Do not clone
native stroke representation or add lossy coding solely to obtain conformance.
Parsed Markdown and report snapshots are immutable, hashable, and sendable;
they have no persistence schema. Native table alignment is not Codable, and
decoding an agent into a newly generated report would lose its captured document.
Their missing Codable conformance is an explicit boundary, not a new parser model.

The editable agent draft may contain incomplete user input; its checked creation
operation enforces the current form rules. Running progress carries an immutable,
checked finite fraction in `0..<1`; completion has its own phase. Simulation
returns replacement agents and receives its step explicitly. Native bindings
edit drafts by reading the current bound value and replacing one field, retaining
the other fields even when several input events arrive before a frame.

## Investigation outcome

| Inspiration | Already provided by SwiftTUI | Chio's useful layer |
| --- | --- | --- |
| Lip Gloss | View layout, padding, borders, colors, style protocols, environment | Semantic tokens and coherent defaults |
| Bubbles | Lists, tables, text editing, scrolling, spinners, progress, command palettes | Search composition, result/empty states, contextual help |
| Huh | Bindings, native input controls, submission, focus | Field presentation, validation visibility, form workflow |
| Glamour | Rich text and links as views; no Markdown parser | Parsed documents composed from themed native views |
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
Consumers use `replacing(...)` on the theme and nested values to customize its
colors without rebuilding styles. Omitted replacement arguments preserve the
receiver's values. Construction and replacement keep the existing nonnegative
spacing and single-printable-cell glyph preconditions.
Component options specify behavior; application composition specifies content.

Changing theme preserves query, stable selection, focus, and entered values.
Native `GroupBox`, `List`, `Table`, `Button`, `TextField`, `TextEditor`, `Picker`,
`Toggle`, `TabView`, `ScrollView`, `ProgressView`, `Spinner`, and native prompt styles share the same
semantic roles. The first appearance closely follows Huh's Charm palette and
Bubbles' selected rows, muted metadata, and compact keyboard help.

Bordered buttons inherit their enclosing surface and show focus or an enabled
press with an accent outline (error for destructive actions). Unfocused outlines
use the ordinary border color; disabled controls retain dimming. Native
focus-effect suppression also suppresses the focused outline. This matches the
accent-outline treatment of text inputs without painting a rectangular focus
fill behind rounded border glyphs: terminal backgrounds cover whole cells and
cannot follow a glyph's curve. Button labels remain authored native content.

## Searchable selection

`SearchableList` has an always-visible search field, stable item IDs, optional
external query binding, `.filtering(.fuzzy)`, and an `.onActivate` callback.
Filtering preserves a visible selection; otherwise it selects the first result,
or `nil` if there are no results. Filtering never activates an item. Editing the
query also commits selection before another control can act on it. Reconciliation
uses the query actually retained by its binding, including when an application
rejects or transforms a write; external query/data changes also reconcile on render.

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
When Return has requested results focus, a second Return activates the current
filtered selection even if native focus is still leaving the editor. No-match
queries remain inert during that handoff.

The persistent `›` marker represents selection. SwiftTUI's native `▌` and row
chrome show keyboard focus, which Tab can move without changing selection.
Enter is scoped to results and activates the reconciled selected ID. Arrow keys
retain native navigation from the focused row. Rows contain passive presentation;
place buttons and editors outside the searchable list.

Attach application shortcuts with `.onResultKeyPress(perform:)`. The
`.onSearchFocusChange` callback is for presentation such as contextual hints;
its render-driven updates must not guard an ancestor's input routing.

## Searchable multiple choice

`SearchableChecklist` combines the existing matcher, native `List` set selection,
and explicit checkmarks. Its binding contains checked stable IDs; native row focus
is an independent cursor. Filtering never edits membership. The default filter is
fuzzy, with optional substring matching and application-owned query binding.
Counts show all checked IDs, hidden checks, and unavailable checks.

An enabled, visible row may be checked or unchecked. Disabled choices remain
visible native focus stops with an Unavailable label, but both toggle directions
are rejected. Checked IDs absent from the source remain in the binding and count
as unavailable. This avoids silently repairing an application's draft: the app
owns membership validation, selection limits, removal policy, and explicit reset.
Changing the source, query, theme, or geometry never auto-selects or prunes IDs.

Native List does not enforce per-row disabled membership itself. A small binding
adapter accepts changes only for the current visible, enabled IDs and preserves
all other current membership. It reads the authoritative query and selection at
dispatch time, including bindings that reject or transform writes. Checkmarks and
counts always read the value the application retained. No parallel selection store
or generic validation framework is introduced.

The checklist starts in search. Return requests focus in a List-only native
namespace, which reaches the first available native row focus region. Arrows move
that focus without changing checks; Space/Return toggles the focused row. Native
activation also routes through the same membership gate. Filtering may change
which item occupies a native row index; Chio promises stable checked IDs, not
stable item focus through arbitrary source reordering. Native scrolling owns reveal.

`/` enters search from results. Escape clears the filter; in search it also returns
to rows when results exist. With no results, Return keeps editing focus. Additional
unmodified input in the search-to-results handoff is consumed until native focus
arrives, preventing an old row from being toggled. The slash-to-search handoff
carries simple type-ahead into the native query, as in `SearchableList`.
`.onResultKeyPress` scopes application shortcuts to the results subtree.

The `--choices` example composes existing `SearchableList` and `FormField` for a
single language, followed by `SearchableChecklist` for capabilities. A complete
language value is always retained in the draft, even if search has no matches.
Search changes the candidate; Next/activation advances the form, and Save commits
the complete draft. The application validates one through three capabilities and
current availability. It preserves values and queries on Back, restores original
choices on Cancel, and captures a local display summary only after successful Save.
Short terminals reduce decorative space while preserving rows, errors, actions,
and keyboard hints. This is a focused form example, not a new form coordinator.

## Composition and layout

`KeyHint` renders one shortcut and explanation; `KeyHints` arranges compact
hints in wrapping rows. `StatusBar` presents compact application status. The dashboard combines
these with searchable agents, details, and native progress.

Narrow terminals must retain usable search and selection, readable status, and
essential shortcuts. Resize and theme switching should preserve interaction state.
The demo exposes successful and failed simulated runs and empty results without
network calls, credentials, or external service setup.

At widths below 88 cells the dashboard stacks its sections; below 26 rows it
prioritizes the list and essential shortcuts. The full layout is intended for
100 × 30 or larger, with a usable compact layout at 36 × 18.

## Contextual keyboard help

Immutable `ShortcutHint` values hold an authored key label, short action label,
and optional expanded detail. `ShortcutGroup` preserves the title and ordered
descriptions, including duplicates. Both synthesize Codable, Hashable and
Sendable. These are display descriptions: labels such as `↑↓` can describe more
than one native key. They neither register actions nor parse strings into input.
The pinned native command registry and its `KeyBinding` are not public.

`KeyHint` and `KeyHints` accept those same values; `KeyboardHelp` presents grouped
headings, hints and wrapping detail. Empty groups are omitted and an entirely
empty collection has an explicit message. Applications derive visible descriptions
from their current context and action availability. Native handlers remain the
authority for execution; Chio introduces no second command registry.

`KeyboardHelp` is passive content suitable for inline use or native presentation.
The example uses `.fullScreenCover` with an authored heading, Close button and
native `ScrollView`. The cover owns modal scope and focus restoration; retain the
background subtree to preserve its focus identity across dismissal. Input
handlers on the whole cover reach both Close and the viewport. Handlers placed
inside a native sheet's content cannot receive keys focused on its outer viewport
or header; no additional sheet style or custom presentation machinery is needed.

The focused `--keyboard-help` example shares descriptions between the footer and
expanded help. `?` opens from results or action buttons; within search it remains
ordinary text. F1 opens the full reference from any control, without deriving a
context from a potentially pending focus transition. Scope printable shortcuts to native
control subtrees, never gate ancestor input using the render-driven search-focus
callback. A retained help context keeps the requested group stable while modal
focus changes. Pending presentation blocks background actions and consumes an
immediate Escape, including several keys delivered before the next frame.
The example only increments a local run count; it performs no agent work.

## Tabs

`.chioTheme` installs `ChioTabViewStyle` on native `TabView` and `Tab` declarations.
Chio provides a compact two-row strip: accent text and a persistent rule mark
selection, while a surface fill marks keyboard focus. Focus-effect suppression
removes that fill without removing selection. Structured native titles, details
and badges use terminal-cell measurement; narrow strips move trailing options
into a More menu. The whole control respects native disabled state.

SwiftTUI owns the selected binding, cursor, routes and content lifecycle. Left/Right
and Home/End move the strip cursor; Return or Space activates it. Down opens
overflow, Up/Down move there, and Escape closes it. Tab/Shift-Tab leave the strip
through ordinary focus navigation. Chio registers no replacement input handlers.
The bounded menu uses native scrolling, revealing the raw native cursor even
when focus paint is suppressed. Its offset is derived, not independently owned;
wheel-driven menu scrolling is not a persistent interaction. An overlay-only
geometry reader bounds the menu to the allocated tab view, without wrapping the
authored content. At least three columns and five rows are needed for a bordered
menu with one option; smaller allocations omit the menu paint. Provide enough
space for the content as well.

SwiftTUI publishes the strip's available width during resolution. In an
unconstrained `HStack`, a later `.frame(width:)` can allocate less than that
published width, so the native visible/overflow partition can still reflect the
terminal width. Native clipping contains paint, but does not clip hit-test regions
or choose a new partition. Pointer routes can consequently extend beyond the
visible strip in that composition. The workspace example is verified at the
documented sizes; arbitrary nested layouts remain an upstream sizing boundary.
Keyboard selection still follows the native tags.

Stable native tab values preserve dormant value state across switching. The
example exercises a counter and editor draft; this is not a promise to retain
arbitrary live resource handles or tasks. Removing a tab or replacing its owning
identity resets native retained state. Invalid selection falls back to the first
live tab without rewriting the application's binding. Empty tabs remain an inert
native focus target; native tabs do not expose per-option disabled state.

The focused `--tabs` example keeps five sections in one native tab view. F6 asks
native focus to return to the strip from an editor, preserving ordinary arrow
editing. Theme changes and compact resizing retain the current values. The
pinned runtime needs a fresh menu frame before subsequent overflow navigation;
Chio does not replay input across that native transition.

## Pagination

`Pagination` is an immutable count, page size and current page for a finite result
set. The count is nonnegative, the size is positive, and the zero-based page index
is nil exactly when the set is empty. These relationships are checked during
construction, replacement and decoding. Ordinary programmer inputs use
preconditions; decoding malformed values throws. The value is Hashable, Codable
and Sendable. Page counts and zero-based item ranges use constant-time arithmetic
that remains valid through `Int.max`; page options are never materialized.

`selectingPage(at:)` returns nil for an invalid index. First/previous/next/last
transitions return replacement values and stay at a boundary. Applications choose
how data changes affect position: `updatingTotalCount(to:)` preserves a valid page
or clamps to the last remaining page, and `resizingPages(to:)` selects the page
containing the old first visible item. Empty-to-nonempty updates start at page one.
Constructing a new value explicitly starts a new result set at its first page.
Counts describe the application's current data; the value performs no loading.

`PageControl(pagination:)` binds the complete value. It composes native Previous
and Next buttons, a page summary and an item-range summary. Empty and single-page
sets have no enabled page actions. Arrows and Home/End are scoped to those native
buttons, leaving nearby editors and viewports in control of their own keys.
Each action reads the retained binding again before computing a transition;
rejected or transformed writes do not create an optimistic local cursor.
Disabled state, focus, activation, pointer input and layout remain native.

The `--pagination` history example filters 23 local records, resets position when
the query changes, and preserves the old first item when switching between three
and five rows per page. Native scrolling reveals rows within the selected page
in short terminals. Query/count/page updates occur in one application binding
setter. No asynchronous paging, unknown totals, item selection across pages or
data-source protocol is introduced.

## Scrolling

`.chioTheme` installs `ChioScrollViewStyle` on native scroll views. Unfocused
indicators use muted text; a focused viewport accents its visible indicators,
while focusing an individual track accents only that axis. Suppressing focus
effects retains muted paint. Native disabled opacity remains unchanged.
Glyphs, reserved track space, insets and inherited backgrounds retain native
defaults, so this style does not alter content sizing or cover authored surfaces.

SwiftTUI owns positions, clipping, keyboard navigation, wheel input, track dragging
and clamping. Indicator visibility remains `.scrollIndicators(_:axes:)` policy.
The style also reaches the native scroll view inside a text editor; descendant
editor focus does not imply viewport focus. Native Lists and Tables have their
own scrolling styles and are unaffected. No viewport wrapper is introduced.

The focused `--viewport` example presents a wide, forty-row local activity log
with an application-owned native `ScrollCellOffset`. Arrows move both axes;
Home/End affect the vertical axis when the body owns focus. Tab visits the
individual indicators and a native reset button; F6 returns to the log. Theme
changes preserve position, and native geometry handles bounds on resize.
The pinned runtime includes a viewport's reserved tracks in focus reveal, so
focusing its body can move the offset one cell on each overflowing axis. Chio
retains native geometry and records this upstream limitation; it does not replay
input or invent a cursor anchor to counteract the reveal.

## Command palette

`ChioPaletteStyle` styles SwiftTUI's native `paletteSheet`; `.chioTheme` installs
it alongside the other control styles. Apply the theme outside the palette
declaration so the declaration receives the style. Apps register actions through
native `Panel`, `keyCommand`, and `paletteCommand` APIs. Chio introduces no
command registry, dispatcher, or presentation coordinator.

The style uses the existing Chio fuzzy matcher and stable command IDs. A native
text field keeps editing focus while arrows or Tab/Shift-Tab move selection.
Return calls the command's native activation; Escape uses native dismissal.
Disabled commands remain visible and inert, and unmatched queries show an empty
state. The selected command remains inside a bounded visible window. Short
terminals omit descriptions; command names and keyboard help remain visible.
`initialQuery` seeds each opening; native editing owns subsequent query changes.
Keyboard handlers use the editor's resolved bindings so reopening after a cover
cannot activate from state retained by an earlier palette lifetime.

Ctrl-K opens the dashboard palette from results, search, or detail controls.
It offers Create agent, Run/Retry selected agent, Open agent report, theme
switching, and pause/resume. Actions requiring an agent are disabled without
selection. Cancel preserves the dashboard query, selection, and native focus.
The dashboard queues the selected action and observes the native presentation
binding returning to false before performing it. This lets native focus return
to the dashboard before opening a report or form. Replacing the palette with a
cover in the same frame would record the departing palette as the focus target
to restore after closing the cover.

The opening input batch can precede the palette's first frame. The dashboard
carries simple text/backspace into the initial query and handles Escape, keeping
those keys out of background shortcuts. Navigation and Return in that initial
handoff are consumed; after native focus arrives, the palette owns all editing
and activation. This is a bounded presentation adapter, not general event replay.
The surrounding full-width dropdown surface and divider remain native SwiftTUI
chrome; `sheetStyle` does not style that palette container in the pinned version.

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
  submission. `recordingExit(from:)` returns new visibility after a field exit;
  `submitting(_:)` returns new visibility plus the first invalid field for an
  application-owned native focus binding. The caller assigns the returned value
  to its native state. Hidden fields are excluded by the app.

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

## Password and multiline input

Native `SecureField` uses the existing `ChioTextFieldStyle`; no password wrapper
or separate masking implementation is needed. SwiftTUI projects the value to
bullets before styling and withholds the secure control's value and text-query
metadata from public semantic snapshots. Application-authored labels, helpers,
and feedback must never interpolate a password. Mask shape and reveal controls
are not public options in the pinned native API.

`ChioTextEditorStyle` places the protected `editorContent` once, adding the Chio
surface, horizontal inset, border, and focused accent. SwiftTUI retains the text
binding, cursor, selection, wrapping, paste, viewport, and single focus stop.
The application bounds the editor's height. Tab moves focus; Return inserts a
newline; Home/End move within a logical line. Password Return uses native
submission when an application supplies `.onSubmit`.

The enabled editor samples its text paint from the surrounding environment
before invoking the style. `.chioTheme` installs both the native style and that
foreground color. A standalone style's theme controls its frame; it cannot
retroactively override the sampled inner text paint. Disabled editor text keeps
SwiftTUI's placeholder paint and dimming; Chio does not apply another opacity
layer or replace the protected editing content to conceal this limitation.

The `--text-entry` example uses made-up password input and ordinary notes. The
application validates a demo minimum of eight password characters and nonblank
notes. Save accepts the local draft and clears the password; only the accepted
notes are retained for feedback comparison. Editing again clears stale success.
Cancel clears both fields, and disabled controls leave Cancel and unlocking
available. There is no authentication, transport, or persistence. Native state
owns the editable strings; no serializable credential model is introduced.

## Confirmation and transient feedback

`ChioPromptStyle` transforms native alert and confirmation-dialog chrome: bounded
width, compact insets and message viewport, theme surface, accent border and
stroke treatment. Bordered prompts reserve at least one vertical cell because
the native border overlays its outer rows; zero would cover the header. It retains the declaration's native header tone and placement.
SwiftTUI owns the title row and close button, modal focus, Escape, restoration,
and dismissal callbacks. Its header background uses native terminal paint;
arbitrary Chio header colors are not exposed by the pinned public API.

Action buttons are authored content. Their roles style and describe actions;
custom actions explicitly clear the presentation binding. Escape and the native
close button dismiss without invoking an authored Cancel closure. Put shared
dismissal effects in `onDismiss` when needed. Direct actions form a horizontal
row; the application may provide a `VStack` for more or longer actions. Prompt
styling cannot automatically reorder or wrap arbitrary action content.

`ChioSpinnerStyle` retains native braille frames and cadence, with muted inactive,
accent active and success finished states. SwiftTUI owns the ticking task,
cancellation, accessibility semantics and reduced-motion first-frame behavior.
Chio adds no animation clock. `.chioTheme` installs both styles.

`ChioToastStyle(theme:tone:)` uses native `TerminalTone` for semantic icon and
border colors, with theme surface and compact bounds. It is supplied explicitly
through `.toast(..., style:)`; there is no environment toast style modifier.
SwiftTUI owns stacking, expiry and dismissal. Toasts retain underlying focus and
do not block editing. They may cover bottom content while visible; they are not
an application notification queue or persistent status history.

The `--feedback` example simulates a publish with a cancellable application task.
Its phase is ready, publishing or published; only one prompt may be presented.
The native presentation bindings retain the projected state storage before
entering deferred authoring contexts. A confirmed publish advances the phase,
and a native toast announces completion.
A destructive alert resets the local result. The task only advances simulated
application state; native controls still own presentation and animation timing.

## File selection

`FilePicker(directory:selection:allowedExtensions:showsHiddenFiles:onConfirm:onCancel:)`
chooses one existing readable regular file. It reuses `SearchableList` and its
native editing, focus and scrolling; Chio adds directory loading,
navigation, file eligibility, error/retry presentation and explicit confirmation.
The application's URL binding is committed only after confirmation succeeds.
Browsing, filtering and cancellation leave the previous committed URL intact.
If the binding rejects the proposed URL, the picker stays open with feedback.
After confirm or cancel, the picker becomes inactive; applications dismiss or
recreate it to start another choice.

The directory is a starting location, not a confinement boundary. Inputs must
be absolute local file URLs. Dot components normalize lexically, and Parent
stops at `/`. File and directory symlinks are followed, including outside the
starting location; display and returned paths retain the chosen symlink route.
Broken links, unreadable entries and special files cannot be confirmed. Entries
sort directories first, then by case-insensitive name with deterministic ties.
Dot files and filesystem-hidden entries are hidden unless explicitly enabled.
A nil extension set allows all regular files; an empty set allows none. Matching
is case-insensitive against the chosen filename's extension, without a leading
dot, and directories remain available. Search filters the current folder only.

Return enters the selected folder or confirms a file; Choose confirms a file.
Backspace at results and Parent move up; Escape clears search. Cancel and Ctrl-G
end the choice. Theme and geometry changes preserve the current folder and
filter. A changed starting directory or hidden-file policy reloads the listing.

An internal actor owns Foundation metadata and enumeration work off the main
actor; the picker owns the actor through native state. Native `.task(id:)`
handles cancellation. Each load or confirmation has a fresh generation, and
completion checks cancellation before reading the exact captured state binding,
then rejects stale generations. Navigation, editing during confirmation, cancel
and disappearance invalidate pending work. Confirmation rechecks current kind
and readability; it does not open a file, read contents, reserve an inode or
guarantee that a later application open will succeed. Blocking filesystem calls
may finish after cancellation, but their results cannot commit a cancelled choice.

The `--files` example reads the local starting folder and shows the selected URL;
it does not modify files. Hosted tests and terminal checks use temporary trees.
The plain `--snapshot` renderer cannot await filesystem work, so this example
rejects that flag rather than claiming a loaded directory snapshot.

## Markdown and agent reports

`MarkdownDocument(source)` parses once into an immutable, `Hashable`, `Sendable`
value. Applications create it when content changes and retain it across view
updates. The third-party AST stays internal. `MarkdownView(document)` consumes
that value and the current Chio theme; callers supply a native vertical
`ScrollView` where needed.

Headings, rich paragraphs, emphasis, strong text, inline code, ordered/unordered
and task lists, nested quotes, fenced code, and rules compose from native views.
Each paragraph is one rich `Text`, so SwiftTUI owns wrapping across styled spans.
Smart punctuation is disabled to preserve technical quotes and hyphens. Fenced
code preserves whitespace in a native horizontal scroll view; Tab can focus it,
then arrows or Home/End navigate its columns. Theme changes retain native offset
and focus. A text marker identifies quotes because the pinned leading-edge border
disappears on one-row content; this is presentation composition, not cell rendering.

Tables retain parsed cells and column alignments, then compose native `Table`
and `TableRow` views. SwiftTUI measures column widths in terminal cells and the
table's natural height. A native horizontal scroll view preserves readable
columns on narrow screens; Tab focuses it, arrows/Home/End move horizontally,
and Shift-Tab returns to the reader. Body cells retain inline styling. Native
headers accept plain labels with uniform theme colors, so header emphasis/code
is displayed as readable text. Report tables are eager, not a large-data grid.

`.chioTheme` installs `ChioTableStyle` on ordinary native tables too, supplying
rounded borders and semantic header colors. The pinned SwiftTUI masks the style's
border paint with its default control chrome; grid borders and their background
remain upstream colors. Markdown body rows use the public `listRowBackground`
modifier for Chio's surface color, retaining contrast in both themes. Keep the
native chrome limitation visible rather than drawing a replacement table.

Links display their destinations, images display alt text and source, and HTML
remains literal. No resource is fetched, no command is executed, and links are
not active. Syntax highlighting and active links remain deferred.

Enter on dashboard results opens a native full-screen report for the selected
agent. The report captures the current agent value and parsed document once; a
running simulation can continue underneath without rewriting the reading view.
Reopening captures the latest state. The content labels the local simulation and
escapes user-authored metadata as literal Markdown text.

The vertical scroll view receives native focus on arrival. Arrows and Home/End
move through the report; Escape closes it and Ctrl-T changes the theme. The header
and wrapping hints remain outside the scroll area, including at 36 × 18. Closing
restores the dashboard query, selection, and native focus. During the input batch
before cover presentation, dashboard shortcuts are consumed so Enter followed by
`q` cannot accidentally quit. SwiftTUI owns the cover and focus restoration.

## Source ownership

| Path | Responsibility |
| --- | --- |
| `Sources/Chio/Domain` | Theme values, shortcut descriptions, pure search/membership decisions, pagination, validation visibility, file observations, and parsed Markdown |
| `Sources/Chio/Execution` | Filesystem loading and confirmation checks |
| `Sources/Chio/Presentation` | Components and environment integration |
| `Sources/Chio/Presentation/Styles` | Native SwiftTUI control styles |
| `Examples/AgentDashboard` | Dashboard and focused control examples, domain rules, presentation, and thin entry point |
| `Tests/ChioTests` | Tests grouped by corresponding responsibility |
| `Tests/ChioDashboardTests` | Simulation, draft rules, report snapshots, and dashboard/form/report/palette interaction |
| `Docs/Site` | Static GitHub Pages showcase and vendored asciinema player |
| `Docs/Media` | Release-terminal screenshots and recordings shared by docs and the showcase |
| `Scripts/docs` | Assemble the static site without building the Swift package |

Only create responsibility groups when they contain useful code. Keep each
independently useful production type in a matching file and protocol conformances
in dedicated extensions, following the project working agreements.
Private nested helpers keep inline conformances where a separate extension would
require widening access. Raw-value enum declarations retain Swift's required
placement. Shared frame recorders live in each test target's `TestSupport` group;
scenario-specific expectations and application fixtures stay beside their suites.

## References and boundaries

The dependency is pinned because SwiftTUI is still evolving. Its published
`SwiftTUIViews` product is the library boundary; the demo uses `SwiftTUI`, and
tests use public `SwiftTUIRuntime` rendering and hosted input APIs without testing SPI.
Swift Markdown 0.9.0 is pinned to revision
`25cb61d3482054b09ae76ca4f281b1bfe7fe5a43`. Its manifest includes conditional Windows
unsafe build flags; a revision dependency permits these without changing upstream.
The parser brings swift-cmark 0.9.0, compiled from source by SwiftPM, with no
separately installed cmark library. Ubuntu 24.04/glibc builds and execution are
verified on ARM64 and x86_64 with Swift 6.4.0. Static musl compilation is blocked in the
pinned SwiftTUI dependency; [Plan.md](Plan.md#linux-and-ci) records the evidence.

Native list focus chrome currently resolves through SwiftTUI's own theme;
Chio's selected row, content, controls, and hints use the Chio theme. Upstream
does not expose its theme environment publicly, so exact customization of the
native focus gutter remains an integration gap. Do not hide this with a second
focus system or a private API dependency. `StatusBar` uses a composed text rule
because the pinned native `Divider` does not honor ambient foreground styling.

Color-depth detection and palette conversion also belong to SwiftTUI. The pinned
ANSI-256 conversion maps dark RGB colors poorly; Chio's default surface becomes
`#5F5F5F` instead of `#211D2A`. True-color SSH sessions should declare
`COLORTERM=truecolor` as documented in [the SSH guide](Examples.md#colors-over-ssh).
Keep the authored palette and
native detection; correcting conversion for limited-color terminals is upstream
work, not a second Chio quantizer or an unconditional true-color override.

- [SwiftTUI style system](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIViews/SwiftTUIViews.docc/Style-System.md)
- [SwiftTUI theme model](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIPrimitives/Styling/Theme.swift)
- [Huh themes](https://github.com/charmbracelet/huh/blob/main/theme.go)
- [Bubbles list](https://github.com/charmbracelet/bubbles/tree/main/list) and [help](https://github.com/charmbracelet/bubbles/tree/main/help)

Charm supplies visual references, not a Go API port. Broader forms, syntax
highlighting, active links, and further products remain deferred while these
concrete workflows are refined.
