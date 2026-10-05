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

Descriptions do not register key bindings. Derive their visibility from your
application's current context; keep actions in native handlers. `KeyboardHelp`
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

Theme values are immutable. Use `replacing(...)` to customize colors, spacing,
or treatments while preserving the original:

```swift
let base = ChioTheme.default
let theme = base.replacing(
    colors: base.colors.replacing(accent: Color(hexRGB: 0x02BF87)),
    spacing: base.spacing.replacing(hintGap: 3)
)
```

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
focus. See [the design](Design.md#tabs) for the native lifecycle and overflow limits.

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
           allowedExtensions: ["swift", "md"], onConfirm: { url in
    // Use the explicitly confirmed URL.
}, onCancel: {
    // Dismiss the picker; selectedFile keeps its previous value.
})
.chioTheme(.default)
```

Omit `allowedExtensions` to allow every regular file; an empty set allows none.
Matching ignores case, and folders stay visible for navigation. Hidden files
are off by default; pass `showsHiddenFiles: true` to include them. File and folder
symlinks work, and the returned URL retains the chosen path. The starting folder
does not restrict navigation. Confirmation rechecks readability and file kind;
applications still handle errors when opening the file themselves.

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
labels with themed colors. Links and images show readable labels and destinations;
HTML is literal. Native table border colors remain an upstream styling limitation.
See [AgentReport](../Examples/AgentDashboard/Domain/AgentReport.swift) for snapshot
ownership and [AgentReportView](../Examples/AgentDashboard/Presentation/AgentReportView.swift)
for the reader.
