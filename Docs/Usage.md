# Using Chio

[Back to Chio](../README.md) · [Runnable examples](Examples.md)

Chio supplies opinionated themes and reusable interactions over SwiftTUI's
native controls. Apply `.chioTheme(...)` to your view hierarchy; SwiftTUI owns
rendering, layout, state, input, focus, and scrolling.

The package exports one `Chio` library. Applications also depend on SwiftTUI
for the native views and runtime. See [Package.swift](../Package.swift) for the
current dependency pins and [the design](Design.md) for interaction contracts.

## Search and keyboard hints

Applications compose SwiftTUI views and import `SwiftTUI` and `Chio`:

```swift
import SwiftTUI
import Chio

struct AgentsView: View {
    let agents: [Agent] // Your Identifiable model, with stable IDs and a name.
    @State private var selection: Agent.ID?

    var body: some View {
        VStack {
            GroupBox("Agents") {
                SearchableList(agents, selection: $selection, searchText: \.name) {
                    Text($0.name)
                }
            }
            StatusBar {
                KeyHints {
                    KeyHint("↑↓", "Navigate")
                    KeyHint("/", "Search")
                }
            }
        }
        .chioTheme(.default)
    }
}
```

Rows are passive views; use `.onActivate` for opening an item
and `.onResultKeyPress` for application shortcuts that must not consume search
text. Native row focus chrome currently remains an upstream styling boundary;
see [the design](Design.md).

## Expanded keyboard help

Share immutable descriptions between a compact footer and grouped help:

```swift
let navigation = [
    ShortcutHint("↑↓", "Navigate", detail: "Move through the visible results."),
    ShortcutHint("/", "Search", detail: "Filter results by name."),
]

// In the application's view body; showsHelp is application-owned @State.
content
    .fullScreenCover(isPresented: $showsHelp) {
        VStack {
            Text("Keyboard shortcuts")
            ScrollView {
                KeyboardHelp([ShortcutGroup("Navigation", shortcuts: navigation)])
            }
            Button("Close") { showsHelp = false }
        }
    }
    .chioTheme(.default)

// The same descriptions, without expanded details:
StatusBar { KeyHints(navigation) }
```

`detail` defaults to `""`; empty details add no expanded text row. The decoder
accepts historical missing or null details as empty, and encoding always emits
the detail string. Descriptions do not register key bindings. Derive their visibility
from your application's current context; keep actions in native handlers. `KeyboardHelp`
supplies content while native containers supply scrolling, dismissal and focus
restoration. Apply `.chioTheme` outside the presentation declaration and keep the
presenting controls mounted while help is open. Scope modal key handlers to the
whole authored cover so they work from both its viewport and its buttons.

For editor-safe `?` handling, use `.onResultKeyPress` on a searchable list and
scoped `.onKeyPress` on action controls. Avoid an ancestor handler that consumes
ordinary text. See [HelpExampleView](../Examples/AgentDashboard/Presentation/HelpExampleView.swift)
for F1 during editing, contextual descriptions, and protection against keys
arriving before presentation acquires focus.

## Themes

Choose `.default`, `.light`, or `.btop`. The btop-inspired preset uses near-black
surfaces, cyan accents and compact spacing through the same semantic roles.

Theme values are immutable. Use `replacing(...)` to customize colors, spacing,
or treatments while preserving the original:

```swift
let base = ChioTheme.default
let theme = base.replacing(
    colors: base.colors.replacing(accent: Color(hexRGB: 0x02BF87)),
    spacing: base.spacing.replacing(hintGap: 3)
)
```

## Compact metrics and history

Combine native groups and progress views with a passive history graph:

```swift
let theme = ChioTheme.btop
let samples: [Double?] = [0.2, 0.45, nil, 0.55, 0.64]

GroupBox("CPU") {
    VStack(alignment: .leading, spacing: 0) {
        ProgressView(value: 0.64, barWidth: 24) {
            Text("Utilization")
        } currentValueLabel: {
            Text("64%")
        }
        .progressViewStyle(ChioProgressViewStyle(theme: theme, treatment: .measurement))
        Sparkline(samples, scale: .fixed(0...1))
            .frame(width: 24, height: 4)
    }
}
.groupBoxStyle(ChioGroupBoxStyle(theme: theme, titlePlacement: .border))
.chioTheme(theme)
```

`.border` puts a display-only title in the top border. Text truncates to one row;
allocations below five columns hide title paint while keeping its subtree mounted.
Content controls retain native focus and input. The default `.content` placement
keeps the heading inside the group. Explicit style options stay independent of
the palette; pass the current theme when constructing those styles.

`.measurement` keeps a progress track accented even at 100%. The default
`.progress` treatment paints completion as success. Native `ProgressView` retains
its progress-bar accessibility role; authored labels supply metric names and units.
Applications own utilization thresholds and alert meaning.

`Sparkline` draws oldest-to-newest, equally spaced samples through SwiftTUI's
braille canvas. Supply only finite readings; use `nil` for gaps. Empty and
all-missing input draw nothing. `.automatic` scales to present values and puts
constant data at the midpoint; a single-entry series sits at the right edge.
`.fixed(...)` requires finite, strictly increasing bounds and clips outliers.
Set a frame to choose the graph's allocation. At narrow widths, each uninterrupted
run retains its first, last, minimum and maximum readings per drawing column.
Subcolumn gaps may be visually indistinguishable, but are never bridged by a line.
The graph supplies an accessible textual summary. Applications own sample
collection, retention, clocks and units.

See the [compact metrics example](Examples.md#compact-metrics) for local sample
updates, missing and empty history, theme changes and adaptive composition.

## Maps

`MapView` draws a north-up world or street map from a retained `MapSource`.
Supply application-owned camera and marker-selection bindings, plus optional
location and route overlays:

```swift
import SwiftTUI
import Chio

struct PlacesView: View {
    let source: MapSource
    let overlays: MapOverlays
    @Binding var camera: MapCamera
    @Binding var selection: String?
    let activate: (MapMarker) -> Void

    var body: some View {
        MapView(source: source, camera: $camera, selection: $selection,
                overlays: overlays, detail: .minimal)
            .mapFills(true)
            .mapLabels(true)
            .onActivate { marker in activate(marker) }
            .frame(width: 100, height: 26)
            .chioTheme(.default)
    }
}
```

Construct and retain checked geography and overlays at the application boundary:

```swift
let start = try MapCoordinate(latitude: 1.289, longitude: 103.866)
let end = try MapCoordinate(latitude: 1.292, longitude: 103.870)
let camera = try MapCamera(center: start, longitudeSpan: 0.030)
let marker = try MapMarker(id: "meeting-place", coordinate: start, title: "Meet here")
let route = try MapRoute(id: "walk", title: "Our walk",
                         path: MapPolyline(coordinates: [start, end]))
let overlays = try MapOverlays(markers: [marker], routes: [route])
```

Coordinates, cameras, source geometry, metadata and overlays are immutable.
Checked constructors and decoding reject invalid values. Marker IDs and route
IDs are separate namespaces; IDs must be unique within their own collection.
Overlays accept at most 256 markers, 64 routes and 200,000 route vertices.
Use `.empty` when no annotations are needed. An empty marker or route title omits
its supporting label. Chio paints supplied paths; applications calculate routes.

While the map has native focus, arrows pan and `+`/`-` zoom around the center.
`n`/`p` cycle through markers in authored order and center the selected location;
Return calls `onActivate` for the selected marker. The map is one focus stop;
Tab/Shift-Tab continue native traversal. Camera and selection bindings remain
authoritative. Unknown selected IDs are retained, and external selection changes
do not implicitly move the camera or activate a location. `.mapLabels(false)`
hides background, route and unselected-marker labels; selected-marker labels remain
enabled and take priority where they fit. Overlapping unselected markers may be
omitted from the drawing, while remaining keyboard-selectable.

Customize water and park fills through `theme.replacing(map:
theme.map.replacing(water: color))`. These colors are independent of syntax
highlighting. Routes use `theme.colors.accent`; selected Braille rings and their
labels use `theme.colors.warning`. Ordinary markers use `theme.colors.foreground`.
Use `.mapFills(false)` for outlines at any detail level. Routes clear nearby
linework and own the dots in each touched cell, avoiding shared-cell colour bleed.

Detail is `.silhouette`, `.minimal` (the default), `.abstract`, or `.source`.
It controls geographic classes, boundary simplification and background labels;
markers and routes remain independent. A themed native Canvas paints geometry,
with native text for labels. Preparation runs asynchronously with bounded work;
obsolete results cannot replace the current request. Overload and compact layouts
show explicit summaries instead of presenting incomplete geography as complete.

Allow at least 32 × 16 drawing cells at longitude spans of 60 degrees or more,
or 58 × 16 for closer views, plus the component’s two source-credit rows.
Smaller layouts retain camera and selection for expansion. Source coverage is a
separate fact from feature bounds: geometry may extend outside the covered area.

Applications load bytes and construct sources before presentation. For normalized
GeoJSON, use `MapDataset.decodeGeoJSON(data)` for the supported subset, then
`MapSource(dataset: dataset, metadata: metadata, coverage: coverage)`. Source
metadata requires attribution, license and source URLs, and a source revision;
`attributionURL` is optional. `MapView` displays source credits in two rows.

`NormalizedGeoJSONMapAdapter(metadata:coverage:)` adapts normalized GeoJSON bytes.
`OpenMapTilesAdapter(tile:metadata:)` adapts MVT bytes with an explicit
`MapTileCoordinate`. Both return the same checked `MapSource` representation;
neither adapter loads files, makes requests, stitches tiles or chooses provider
resolution. Applications choose when to acquire sources and retain responsibility
for provider choice and data licenses.
See the [runnable example](Examples.md#maps) and its
[fixture provenance](../Examples/Maps/Fixtures/Provenance.md).

### Online vectors

Opt into networking at the application boundary. The view itself stays offline:

```swift
let endpoint = try await OpenMapTilesSource.fetchOpenFreeMap()
let loader = MapTileLoader(source: endpoint) // Retain one loader per map consumer.
let request = MapTileRequest(camera: camera, viewport: viewport)
let snapshot = try await loader.load(request)
// Publish snapshot.source only if request still matches the current camera/allocation.
```

Get the actual drawable allocation with `.onViewportChange { viewport = $0 }`.
Nil means the compact fallback is visible. Use SwiftTUI's `.task(id:)` to load
when the camera/allocation changes, retain the previous source during loading,
and check cancellation before publication. Start with `MapView(source: nil, ...)`
when nothing has loaded; its controls and allocation reporting remain available. See the complete
[online example composition](../Examples/Maps/Presentation/OnlineMapContent.swift).
Changing theme or `MapDetail` does not change a tile request.

For another OpenMapTiles-compatible service, construct
`OpenMapTilesSource(template:zoomRange:metadata:)` with a path such as
`https://your-host.example/tiles/{z}/{x}/{y}.pbf`. Placeholders must occur exactly
once in the path; source metadata and zoom limits are required. URL construction
is pure. Discovery and `load` are explicit async operations.

The loader acquires the whole viewport with at most two concurrent requests and
16 tiles. It retains a bounded memory cache, cancels superseded work, and fails
instead of returning partial coverage. It validates selected source parts and
retains complete parts whose bounds could intersect the viewport; coverage describes
that retained region, even when whole raw tiles are cached. Geometry-budget failures may retry two
lower source zooms; compare `requestedZoom` and `attainedZoom` to disclose that
fallback. Empty successful tiles remain empty; HTTP failures remain errors.
Source zoom 1 is the online minimum; four tiles cover the world through the same
loader used for regions and streets. Online mode never substitutes bundled geography.
Buffered/clipped polygon seams are still possible. See
[online acquisition contracts](Decisions/OnlineMaps.md) for limits and lifecycle.

## Tabs

Use SwiftTUI's tab declarations with stable values; the theme supplies their style:

```swift
// selection is application-owned @State.
TabView(selection: $selection) {
    Tab("Overview", value: "overview") { OverviewView() }
    Tab("Notes", value: "notes") { NotesView() }
    Tab("Activity", badge: "4", value: "activity") { ActivityView() }
}
.chioTheme(.default)
```

Accent text and the rule show selection; a filled label shows keyboard focus.
Arrows choose a tab, Return or Space opens it, and Tab enters its controls.
Narrow layouts expose trailing tabs through More. Give the tab view a bounded
height with room for its content; the overflow menu needs at least three columns
and five rows including the strip and border. Stable native tab values retain
value state when switching away and back. Keep durable data in an application owner if it must
survive removing tabs or replacing the tab view's identity.

The [tabs example](Examples.md#tabs) demonstrates editing, scrolling and native
focus. See [the design](Decisions/Tabs.md#tabs) for the native lifecycle and overflow limits.

## Pagination

Bind an immutable pagination value to native page actions:

```swift
@State private var pagination = Pagination(totalCount: 23, pageSize: 5)

// In the view body, render items[pagination.itemRange] and then:
PageControl(pagination: $pagination)
    .chioTheme(.default)
```

The control displays the current page and item range. Tab focuses an available
arrow button; Return/Space activates it. Left/Right and Home/End navigate while
the page controls are focused. Empty results say “No pages”; empty and single-page
sets disable both actions.

When the data changes, choose the position policy explicitly:

```swift
pagination = pagination.updatingTotalCount(to: items.count) // Keep/clamp page.
pagination = pagination.resizingPages(to: 10) // Keep the old first item in view.
pagination = Pagination(totalCount: filtered.count, pageSize: 10) // Reset page.
```

Counts must be nonnegative and page sizes positive. `pageIndex` is zero-based and
nil for an empty set. `selectingPage(at:)` returns a replacement or nil for an
invalid page. Give `PageControl` at least 20 columns for ordinary summaries;
large numbers truncate within the available width. The application owns data and
loading. See the [history example](Examples.md#pagination) for filtering and sizing.

## Scrolling

Native scroll views acquire Chio's muted indicators and accent focus treatment:

```swift
@State private var position = ScrollCellOffset.zero

// In the view body:
ScrollView([.horizontal, .vertical], position: $position) {
    ActivityLog()
}
.frame(height: 16)
.chioTheme(.default)
```

Give the viewport a finite size along its scrolling axes. Use native
`.scrollIndicators(.hidden)` to hide tracks, or `.scrollViewStyle(...)` inside
the theme scope to override the style. Custom theme `mutedText` and `accent`
colors control idle and focused indicators. Content backgrounds remain authored.
Focus-effect suppression keeps the indicators muted without disabling scrolling.

The native runtime retains keyboard, wheel, drag and position ownership.
For a two-axis viewport, Home/End act vertically; focusing its horizontal track
lets Home/End act horizontally. The [viewport example](Examples.md#scrolling)
demonstrates this directly. Native Lists and Tables use their own styles.
The pinned runtime can nudge the position by one cell when focus enters a
viewport with reserved tracks. Home then Left corrects the initial one-cell
nudge; Left otherwise moves only one column. This also occurs with SwiftTUI's
automatic style.

## Expandable groups

Style native disclosure groups through the theme:

```swift
@State private var expanded = false

// In the view body:
DisclosureGroup("Details", isExpanded: $expanded) {
    Text("Build settings and notes go here.")
}
.chioTheme(.default)
```

Nest groups to build a hierarchy, or disclose ordinary controls and help text.
The theme supplies a compact header, focus highlight and indentation. Native
Tab/Shift-Tab moves focus; Return/Space or clicking the header toggles expansion.
Clicks on content leave the parent open. Theme colors customize this treatment,
and a nearer `.disclosureGroupStyle(...)` can override it.

Keep bindings for values that must survive collapse in an owner outside the
group. SwiftTUI removes collapsed content; it does not archive arbitrary child
state. Native arrows move focus geometrically, without tree-specific expand/
collapse commands. See the [project-tree example](Examples.md#expandable-tree)
for parent-owned expansion choices and native scrolling.

## Command palettes

`ChioPaletteStyle` styles SwiftTUI's native command palette. Apply `.chioTheme(...)`
after `.paletteSheet(...)` so the palette declaration receives the theme's style.
Keep command registration and presentation in native SwiftTUI APIs; the
[dashboard example](Examples.md#dashboard) demonstrates filtering and activation.

## Forms

Forms use the same native composition. `FormField` supplies consistent headings,
help, and inline errors; immutable `FormValidation<Field>` controls when current
errors become visible. Assign the value returned by `recordingExit(from:)` after
blur. `submitting(issues)` returns a tuple with the new `validation` value and
`firstInvalidField`; assign the former and use the latter for native focus.
Applications own the validation rules, bindings, and native focus requests. See
[CreateAgentView](../Examples/AgentDashboard/Presentation/CreateAgentView.swift) for
the complete workflow and [AgentDraft](../Examples/AgentDashboard/Domain/AgentDraft.swift)
for its pure validation rules.

`description` defaults to `""`; empty descriptions add no helper row. Errors retain
presence: `error: nil` means no visible issue, while a present message takes
precedence over the description, including an empty message.

For grouped editing, put explicit stacks of `FormField` controls inside native
`GroupBox` views, with Save/Cancel outside the scrolling fields. Keep conditional
field values in a parent-owned draft; validate the visible fields against the
current draft, including relationships between fields. Replace the saved snapshot
only on successful validation, and restore that snapshot on Cancel. The
[grouped settings example](Examples.md#grouped-forms) demonstrates these choices
without introducing a form coordinator or a separate focus system.

## Multiple choices

For multiple choices, bind a set of stable IDs:

```swift
SearchableChecklist(capabilities, selection: $selectedIDs,
                    searchText: \.name, isEnabled: \.isAvailable) { capability in
    Text(capability.name)
}
.filtering(.fuzzy)
```

Filtering changes the visible rows, never the checked set. Removed IDs and already
checked disabled choices remain in the application binding and are reported as
unavailable; disabled choices cannot be toggled. Applications explicitly validate,
clear, or replace them. Selection limits and submit/cancel behavior belong to the
form, as shown by [the choice example](../Examples/AgentDashboard/Presentation/ChoiceExampleView.swift).
Use `.onResultKeyPress` for ordinary-character shortcuts scoped to results.
Return into results completes at the next frame; additional keys in that same
input batch are consumed so they cannot toggle an old row.

## Text entry

Use native SwiftTUI controls inside Chio’s field presentation:

```swift
VStack {
    FormField("Password") {
        SecureField("Password", text: $password)
    }
    FormField("Notes") {
        TextEditor(text: $notes).frame(height: 8)
    }
}
.chioTheme(.default)
```

`SecureField` inherits `ChioTextFieldStyle`; `ChioTextEditorStyle` surrounds the
native editor with theme colors and a focus border. SwiftTUI owns masking,
editing, selection, wrapping, and scrolling. Give the editor a bounded height
when it should scroll. Native `.onSubmit` handles Return in a password field;
Return in a multiline editor always edits the text.

Apply `.chioTheme(...)` to customize enabled editor text along with its frame.
The pinned native editor supplies its own disabled text color and dimming, so
that inner disabled color is not currently a Chio theme token.

## Confirmation and feedback

`.chioTheme(...)` installs `ChioPromptStyle` for native alerts/confirmation dialogs
and `ChioSpinnerStyle` for native `Spinner` stages. Toast styles are passed explicitly:

```swift
content
    .toast("Saved", isPresented: $showsToast,
           style: ChioToastStyle(theme: theme, tone: .success))
    .chioTheme(theme)
```

Native prompts retain their header paint and modal focus behavior. Custom action
closures must clear their presentation binding; a button role alone does not
dismiss a prompt. Keep action labels short, or compose a `VStack` in the action
builder when a vertical arrangement fits better.

## File selection

```swift
FilePicker(directory: startingDirectory, selection: $selectedFile,
           allowedExtensions: .only(["swift", "md"]), onConfirm: { url in
    // Use the explicitly confirmed URL.
}, onCancel: {
    // Dismiss the picker; selectedFile keeps its previous value.
})
.chioTheme(.default)
```

Omit `allowedExtensions` or pass `.all` to allow every regular file; `.only([])`
allows none. `.only([""])` permits extensionless files. Matching ignores case,
and folders stay visible for navigation. Hidden files
are off by default; pass `showsHiddenFiles: true` to include them. File and folder
symlinks work, and the returned URL retains the chosen path. The starting folder
does not restrict navigation. Confirmation rechecks readability and file kind;
applications still handle errors when opening the file themselves.

For callers of the earlier optional APIs, replace `allowedExtensions: values`
with `allowedExtensions: .only(values)`, and replace `nil` with `.all` or omit the
argument. Pass `optionalDescription ?? ""` or `optionalDetail ?? ""` when adapting
external optional text to `FormField` or `ShortcutHint`. Selection, errors and
`replacing(...)` arguments retain their existing optional semantics.

## Markdown

Markdown also composes with native views. Parse when the source changes and pass
the retained value to `MarkdownView`; avoid reparsing inside a frequently updated
`body`:

```swift
struct ReportView: View {
    let document: MarkdownDocument // Created by the content owner when its source changes.

    var body: some View {
        ScrollView {
            MarkdownView(document)
        }
        .chioTheme(.default)
    }
}
```

The first Markdown slice supports headings, paragraphs, strong/emphasized text,
inline and fenced code, lists, quotes, rules, and aligned tables with native
horizontal scrolling. Table body cells retain rich text; native headers use plain
labels with themed colors. Passive links and images show readable labels and destinations;
HTML is literal. Native table border colors remain an upstream styling limitation.

Swift fences highlight automatically: the first word of the fence information
must be `swift` (case-insensitive). Unknown and unlabeled code stays plain. Code
parsing and token classification happen when `MarkdownDocument` is constructed,
so retain the document through theme and view updates. To read all code in plain
foreground paint:

```swift
MarkdownView(document).codeHighlighting(.plain)
```

The default is `.automatic`. This modifier also works on the interactive-link
initializer below and retains its opening action. Customize token colors through
the theme:

```swift
let theme = ChioTheme.default.replacing(
    syntax: ChioTheme.default.syntax.replacing(keyword: .cyan, comment: .white)
)
MarkdownView(document).chioTheme(theme)
```

`theme.syntax` has `keyword`, `type`, `string`, `number`, and `comment` roles;
plain identifiers, punctuation, and operators inherit the enclosing foreground,
normally `theme.colors.foreground` (secondary text inside a quote).
Code over 65,536 UTF-8 bytes remains plain. Parsing also has a deterministic
4,096-progress-checkpoint budget; cancellation displays the whole block plainly.
This is a work bound at parser callbacks, not a hard time or memory limit. The
Swift grammar may not recognize every latest language feature. Highlighting keeps
malformed and partially recognized code literal, and colors a complete string,
including interpolation, with one role. It retains parsed source text, blank rows,
and trailing newlines in one native rich `Text` within the existing horizontal
scroll view. Tab focuses the code; arrows and Home/End navigate its columns. Markdown parsing normalizes
CRLF to LF, and the pinned native renderer displays tabs as one cell without
tab-stop expansion.

To enable links, supply SwiftTUI's native action explicitly:

```swift
MarkdownView(document, openLink: OpenLinkAction { destination in
    selectedDestination = destination.rawValue
    return true // The application handled this destination.
})
```

Here `selectedDestination` is application state. The callback can route to another
view, show a destination, or apply the app's opening policy. Return `false` to
leave a destination unhandled; Chio does not then invoke an outer/system opener.
Relative paths and fragments are delivered unchanged. Rendering never invokes
the action, and the original initializer remains passive.

Use Tab/Shift-Tab and Return/Space for native link navigation and activation.
Traversal reaches visible native focus targets; focus the containing scroll view
and scroll to reveal links farther down a document or across a wide table.
Rich labels wrap with surrounding prose and remain one focus stop. Empty
Markdown destinations stay passive. Table body links can activate; native table
headers keep their plain readable fallback. `.disabled(true)` suppresses native
link interaction. `.chioTheme` also styles ordinary SwiftTUI `Link` values;
use a nearer `.linkStyle(...)` to customize their presentation. Active Markdown
code labels inherit link paint so focus remains visible.

See [AgentReport](../Examples/AgentDashboard/Domain/AgentReport.swift) for snapshot
ownership and [AgentReportView](../Examples/AgentDashboard/Presentation/AgentReportView.swift)
for the reader.

## Duration labels

Present durations from your application's state or a native timeline:

```swift
DurationText(elapsed: .seconds(83))             // 1:23
DurationText(remaining: .milliseconds(12_250))  // 0:13
```

Apply `.chioTheme(...)` around the composition. Elapsed fractions round down;
positive remaining fractions round up. Formats are `m:ss` and `h:mm:ss`, with
hours continuing past 24. Inputs range from zero through
`Duration.seconds(Int64.max)`. Both labels use accent color and readable spoken
accessibility labels.

The application owns measurement, countdown limits, pause/resume and expiry
behavior; SwiftTUI's `TimelineView` can drive presentation updates. The
[focused example](Examples.md#timers-and-stopwatches) demonstrates one application
implementation. Its internal
[`ElapsedTime`](../Examples/AgentDashboard/Domain/ElapsedTime.swift) helper is no
longer exported by Chio. Code using that experimental API must move its timing
state into the application; `DurationText` is unchanged. The existing demo and
recording retain their behavior.
