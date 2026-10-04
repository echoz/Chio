# Chio

**Beautiful terminal interfaces for Swift.**

*Chio* means attractive or pretty in Singlish. Chio is an opinionated,
declarative design and interaction layer over [SwiftTUI](https://github.com/SwiftTUI/swift-tui),
with a coherent default appearance and value-based theme customization.

The initial look follows [Huh's Charm palette](https://github.com/charmbracelet/huh/blob/main/theme.go)
and [Bubbles' list and help treatment](https://github.com/charmbracelet/bubbles).
The APIs follow Swift composition and native SwiftTUI styles.

## Development and stability

Chio is a **personal project built with Codex assistance and human curation**.
Codex contributes to implementation, tests, and documentation, while the human
maintainer guides the project's direction, design, and what to keep.

It is built primarily for personal use and shared for anyone who finds it useful.
We cannot vouch for its stability or suitability for production use. APIs and
behavior may change without notice. Automated tests cover specific workflows,
not every terminal, platform, or integration; evaluate it for your own needs
before relying on it.

## Current status

The package includes one public library, `Chio`, and the `chio-dashboard`
executable. Run it to try search, selection, agent creation, inline validation,
progress, themes, a command palette, and Markdown reports of simulated runs.
Focused `--choices`, `--text-entry`, and `--feedback` examples exercise richer
controls and confirmation workflows.
They require no external services.

The initial demo slices explore the design direction; Chio's component coverage
remains much smaller than Charm's ecosystem. See the [component coverage map](Docs/Plan.md#component-coverage)
for delivered scopes, native SwiftTUI foundations, and proposed next slices.

## Try the dashboard

Use Swift 6.4 or later on macOS 15 or later, matching the pinned upstream requirements:

```sh
swift run -c release chio-dashboard
```

Use release mode for interactive use. SwiftTUI enables additional verification
in debug builds; plain `swift run` uses debug mode and can feel noticeably slower.

Or build once and run the binary directly:

```sh
swift build -c release --product chio-dashboard
.build/release/chio-dashboard
```

Use arrows to navigate, `/` to search, Enter to open a report, and Escape to clear search.
While browsing: `r` starts a run, `f` simulates failure, `p` pauses progress,
`e` toggles empty data, `t` changes theme, and `q` quits. Ctrl-C also exits.
The `›` marker is selection; the native `▌` shows the current list navigation
target. Tab moves native focus; Enter opens the selected agent's report.

Press **Ctrl-K** for the command palette, including while editing the dashboard
search. Type to filter actions, use arrows or Tab/Shift-Tab to select, Enter to
run, and Escape to cancel. Create an agent, run/retry the selected agent, open its
report, change theme, or pause/resume the demo from this menu. Cancel returns to
the same search and focus; actions requiring selection are disabled when absent.

Reports capture the run at the moment you open them. Use arrows or Home/End to
scroll, Ctrl-T to change theme, and Escape to return to the same selection and
filter. Reopen for the latest run state. Tab can focus a code block, where left
and right scroll long lines. The reports demonstrate headings, rich text, lists,
quotes, code, and tables. The **Table example** near the top shows aligned columns
and illustrative timings. Tab focuses it; left/right scroll on narrow screens,
and Shift-Tab returns to vertical reading.

Press `n` while browsing to create an agent. Enter its name, choose a role with
the arrow keys, and use Space to toggle Start immediately. Test agents also
require a suite name. Tab and Shift-Tab move between controls. Create or Ctrl-S
submits; Return in a text field also submits. Invalid submission shows inline
errors and focuses the first invalid field. Escape cancels; Ctrl-T changes theme
while preserving the draft. Successful creation clears the filter and selects
the new agent. Created agents are simulated and last only for the current session.

Try 100 × 30 for the full dashboard. Narrow windows stack the sections; short
windows prioritize the list and essential hints. The compact layout fits 36 × 18.

Capture deterministic plain-text frames without a terminal:

```sh
swift run chio-dashboard --snapshot --width 100 --height 30
swift run chio-dashboard --snapshot --width 50 --height 30 --scenario failed
```

Other scenarios are `empty`, `no-matches`, and `completed`. Use `--light` for the
alternate palette or `--paused` to start an interactive demo without advancing
the simulation.

Linux verification uses Swift 6.4.0 on Ubuntu 24.04. Ordinary Linux builds use
glibc and need the Swift runtime libraries; they are not self-contained binaries.
Static Linux distribution is a separate compatibility check, described below.

### Try choice fields

Run the focused two-step form using the same executable:

```sh
COLORTERM=truecolor swift run -c release chio-dashboard --choices
```

Search for a language and press Enter to continue, then choose one to three
capabilities. In the checklist, Enter leaves search for native rows; arrows move
focus and Space or Enter toggles a check. `/` returns to search and Escape clears
the filter. Checked items stay selected when a filter hides them. Deploy is
visible but unavailable in this local demo.

Ctrl-S advances or saves, Ctrl-B goes back, and Ctrl-X cancels and restores the
original choices. Ctrl-R resets the draft, Ctrl-T changes theme, and Ctrl-Q quits.
Save validates the complete selection, including hidden checks; it never silently
truncates it. The example keeps its saved summary only for the current process.
Use `--choices --snapshot` for a noninteractive language-page capture.

### Try text entry

```sh
COLORTERM=truecolor swift run -c release chio-dashboard --text-entry
```

Enter a made-up password and some notes. Tab and Shift-Tab move between the
native controls; Return in Notes inserts a newline, and multiline paste keeps
its line breaks. Ctrl-S validates the demo's eight-character password minimum
and required notes, then clears the password and shows acceptance. Nothing is
authenticated, sent, or persisted. Ctrl-X clears both fields; Ctrl-D locks or
unlocks editing; Ctrl-T changes theme; Ctrl-Q quits. The example fits 36 × 18.
Use `--text-entry --snapshot` for a deterministic capture.

The same controls compose directly in an application:

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

### Try confirmation and feedback

```sh
COLORTERM=truecolor swift run -c release chio-dashboard --feedback
```

Press Publish (or Ctrl-P), then Tab to Cancel or Publish and press Return.
Escape dismisses the prompt. A local simulated publish shows the native spinner,
then a success toast that expires after three seconds. Discard (Ctrl-D) becomes
available after completion and opens a destructive confirmation. On the main screen, Ctrl-T changes
theme and Ctrl-Q quits. Nothing is sent or persisted. The example fits 36 × 18;
`--feedback --snapshot` captures its initial state without a terminal.

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

### Colors over SSH

For a true-color terminal such as Blink, declare that capability on the remote
host when launching the dashboard:

```sh
COLORTERM=truecolor .build/release/chio-dashboard
# Or build and run:
COLORTERM=truecolor swift run -c release chio-dashboard
```

SSH may not forward `COLORTERM`. With only `TERM=xterm-256color`, the pinned
SwiftTUI renderer falls back to 256 colors and incorrectly maps Chio's dark plum
background (`#211D2A`) to gray (`#5F5F5F`). The launch prefix preserves the authored
RGB palette through SwiftTUI's existing capability detection and applies only to
that process. `NO_COLOR` remains respected; `--force-color` does not select true
color. This addresses a missing capability declaration on true-color terminals;
the upstream conversion still needs correction for actual 256-color terminals.

## Design direction

- Apply a theme to native `GroupBox`, `List`, `Table`, `TextField`, `SecureField`, `TextEditor`, `Picker`, `Toggle`, `ProgressView`, `Spinner`, and native prompt styles.
- Compose reusable `KeyHint`, `KeyHints`, `StatusBar`, `SearchableList`, `SearchableChecklist`, and `FormField` views.
- Customize nested semantic colors, spacing, and treatments through `.chioTheme(...)`.
- Style native command palettes with `ChioPaletteStyle`; apply `.chioTheme(...)`
  after `.paletteSheet(...)` so the palette declaration receives the style.
- Keep SwiftTUI responsible for rendering, state, input, focus, scrolling, and lifecycle.

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

Theme values are immutable. Use `replacing(...)` to customize colors, spacing,
or treatments while preserving the original:

```swift
let base = ChioTheme.default
let theme = base.replacing(
    colors: base.colors.replacing(accent: Color(hexRGB: 0x02BF87)),
    spacing: base.spacing.replacing(hintGap: 3)
)
```

Rows are passive views; use `.onActivate` for opening an item
and `.onResultKeyPress` for application shortcuts that must not consume search
text. Native row focus chrome currently remains an upstream styling boundary;
see [the design](Docs/Design.md).

Forms use the same native composition. `FormField` supplies consistent headings,
help, and inline errors; immutable `FormValidation<Field>` controls when current
errors become visible. Assign the value returned by `recordingExit(from:)` after
blur. `submitting(issues)` returns a tuple with the new `validation` value and
`firstInvalidField`; assign the former and use the latter for native focus.
Applications own the validation rules, bindings, and native focus requests. See
[CreateAgentView](Examples/AgentDashboard/Presentation/CreateAgentView.swift) for
the complete workflow and [AgentDraft](Examples/AgentDashboard/Domain/AgentDraft.swift)
for its pure validation rules.

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
form, as shown by [the choice example](Examples/AgentDashboard/Presentation/ChoiceExampleView.swift).
Use `.onResultKeyPress` for ordinary-character shortcuts scoped to results.
Return into results completes at the next frame; additional keys in that same
input batch are consumed so they cannot toggle an old row.

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
See [AgentReport](Examples/AgentDashboard/Domain/AgentReport.swift) for snapshot
ownership and [AgentReportView](Examples/AgentDashboard/Presentation/AgentReportView.swift)
for the reader.

## Verification

`swift test -c release --no-parallel` covers search and validation rules, public hosted input, themed
terminal cells, true-color terminal emission, `NO_COLOR`, hint wrapping, and
dashboard/form/report layouts. Form interactions include conditional fields, first-invalid
focus, creation, cancellation, theme changes, resizing, and batched input.
Markdown checks cover parsing, rich text wrapping, preserved code whitespace,
native scrolling, report snapshots, and returning to the dashboard's focus.
Palette checks cover filtering, disabled actions, long lists, and focus restoration.
Pass `--no-parallel` explicitly: concurrent hosted dashboard suites can exceed
their frame deadlines on this toolchain. Use the optimized build for the complete
suite: unoptimized multi-screen rendering can exceed the same five-second waits
on slower runners even when the expected focus and content arrive correctly.
On the current macOS Command Line Tools toolchain, SwiftPM fails to
discover the installed Testing macro plugin;
the verified workaround is:

```sh
swift test -c release --no-parallel -Xswiftc -load-plugin-library \
  -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
```

This flag is a local toolchain workaround, not a package dependency. Some native
dashboard measurements also emit an upstream `collection.unboundedRealization`
warning for the four demo rows; virtualization of large datasets is not validated.

Run the complete CI sequence locally with Swift 6.4 and Python 3 installed:

```sh
bash Scripts/ci/verify.sh
```

It runs every test in release mode and debug checks for library controls, domain
values, raster layouts, and the focused examples. The three multi-screen dashboard
suites run only in release; their debug-only upstream runtime diagnostics are not
covered by this CI sequence. `swift test --no-parallel` remains available for a
full debug investigation. Test assertions and deadlines are identical in both modes.
The script also builds the release dashboard, captures snapshot scenarios,
and exercises the executable through a real pseudo-terminal. The smoke check
verifies raw input, search, palette cancellation, report/table and form opening,
focus restoration, normal exit, and restored terminal attributes. This is not a
live Blink/SSH check or a color/latency benchmark. To check an existing binary:

```sh
python3 Scripts/ci/terminal-smoke.py .build/release/chio-dashboard
```

[CI](.github/workflows/ci.yml) runs on pushes to `main` and pull requests using
Xcode 27 on macOS and the official Swift 6.4.0 Ubuntu image on Linux. The macOS
`xcode-27` runner is currently a public preview. Jobs retain verification logs and
plain-text snapshots; generated artifacts are not committed.

The manual [Static Linux compatibility](.github/workflows/static-linux.yml)
workflow installs the checksum-verified Swift 6.4.0 Static Linux SDK, attempts a
release build against the same dependency pins, then checks ELF linkage and runs
the terminal smoke check if compilation succeeds. It fails visibly when upstream
compatibility prevents a build; it does not patch dependency sources or suppress
failures. The current blockers and verified platforms are recorded in
[the plan](Docs/Plan.md#linux-and-ci).

## Repository

`Sources/Chio/Domain` owns theme values, pure search rules, validation visibility, and parsed Markdown.
`Sources/Chio/Presentation` owns views and styles, with native styles in `Presentation/Styles`.
`Examples/AgentDashboard` owns the simulated demo; `Tests/ChioTests` mirrors library
responsibilities and checks rendering and behavior without requiring a real TTY.

The dependency is pinned to inspected SwiftTUI revision
`2d84ac7083993da2ef52e9d3d30255467efb9553`; this is a revision pin, not a validated release tag.
The Markdown parser uses Swift Markdown 0.9.0 at revision
`25cb61d3482054b09ae76ca4f281b1bfe7fe5a43`, plus its source-built swift-cmark dependency.
Parser types are not exposed through Chio's public API.

Read [the design](Docs/Design.md) for contracts and [the plan](Docs/Plan.md) for
milestones and acceptance gates. Upstream references:
[style system](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIViews/SwiftTUIViews.docc/Style-System.md),
[theme model](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIPrimitives/Styling/Theme.swift).
