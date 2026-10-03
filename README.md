# Chio

**Beautiful terminal interfaces for Swift.**

*Chio* means attractive or pretty in Singlish. Chio is an opinionated,
declarative design and interaction layer over [SwiftTUI](https://github.com/SwiftTUI/swift-tui),
with a coherent default appearance and value-based theme customization.

The initial look follows [Huh's Charm palette](https://github.com/charmbracelet/huh/blob/main/theme.go)
and [Bubbles' list and help treatment](https://github.com/charmbracelet/bubbles).
The APIs follow Swift composition and native SwiftTUI styles.

## Current status

The package includes one public library, `Chio`, and the `chio-dashboard`
executable. Run it to try search, selection, agent creation, inline validation,
progress, themes, and successful or failed simulated runs. It requires no external services.

This is an early API to learn from, not a stable release. Broader forms and
Markdown remain deferred.

## Try the dashboard

Use Swift 6.4 or later on macOS 15 or later, matching the pinned upstream requirements:

```sh
swift run chio-dashboard
```

Or build once and run the binary directly:

```sh
swift build --product chio-dashboard
.build/debug/chio-dashboard
```

Use arrows to navigate, `/` to search, Enter to open, and Escape to clear search.
While browsing: `r` starts a run, `f` simulates failure, `p` pauses progress,
`e` toggles empty data, `t` changes theme, and `q` quits. Ctrl-C also exits.
The `›` marker is selection; the native `▌` shows the current list navigation
target. Tab moves native focus; Enter opens the selected item.

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

Linux is an intended target but is unverified in this repository. Static Linux
distribution with musl is also unverified and depends on upstream compatibility.

### Colors over SSH

For a true-color terminal such as Blink, declare that capability on the remote
host when launching the dashboard:

```sh
COLORTERM=truecolor .build/debug/chio-dashboard
# Or build and run:
COLORTERM=truecolor swift run chio-dashboard
```

SSH may not forward `COLORTERM`. With only `TERM=xterm-256color`, the pinned
SwiftTUI renderer falls back to 256 colors and incorrectly maps Chio's dark plum
background (`#211D2A`) to gray (`#5F5F5F`). The launch prefix preserves the authored
RGB palette through SwiftTUI's existing capability detection and applies only to
that process. `NO_COLOR` remains respected; `--force-color` does not select true
color. This addresses a missing capability declaration on true-color terminals;
the upstream conversion still needs correction for actual 256-color terminals.

## Design direction

- Apply a theme to native `GroupBox`, `List`, `TextField`, `Picker`, `Toggle`, and `ProgressView` styles.
- Compose reusable `KeyHint`, `KeyHints`, `StatusBar`, `SearchableList`, and `FormField` views.
- Customize nested semantic colors, spacing, and treatments through `.chioTheme(...)`.
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

Copy `ChioTheme.default` and change its semantic colors, spacing, or treatments
to customize it. Rows are passive views; use `.onActivate` for opening an item
and `.onResultKeyPress` for application shortcuts that must not consume search
text. Native row focus chrome currently remains an upstream styling boundary;
see [the design](Docs/Design.md).

Forms use the same native composition. `FormField` supplies consistent headings,
help, and inline errors; `FormValidation<Field>` controls when current errors
become visible and returns the first invalid field on submission. Applications
own the validation rules, bindings, and native focus requests. See
[CreateAgentView](Examples/AgentDashboard/Presentation/CreateAgentView.swift) for
the complete workflow and [AgentDraft](Examples/AgentDashboard/Domain/AgentDraft.swift)
for its pure validation rules.

## Verification

`swift test` covers search and validation rules, public hosted input, themed
terminal cells, true-color terminal emission, `NO_COLOR`, hint wrapping, and
dashboard/form layouts. Form interactions include conditional fields, first-invalid
focus, creation, cancellation, theme changes, resizing, and batched input.
On the current macOS Command Line Tools toolchain, SwiftPM fails to
discover the installed Testing macro plugin;
the verified workaround is:

```sh
swift test -Xswiftc -load-plugin-library \
  -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
```

This flag is a local toolchain workaround, not a package dependency. Some native
dashboard measurements also emit an upstream `collection.unboundedRealization`
warning for the four demo rows; virtualization of large datasets is not validated.

## Repository

`Sources/Chio/Domain` owns theme values, pure search rules, and validation visibility.
`Sources/Chio/Presentation` owns views and styles, with native styles in `Presentation/Styles`.
`Examples/AgentDashboard` owns the simulated demo; `Tests/ChioTests` mirrors library
responsibilities and checks rendering and behavior without requiring a real TTY.

The dependency is pinned to inspected SwiftTUI revision
`2d84ac7083993da2ef52e9d3d30255467efb9553`; this is a revision pin, not a validated release tag.

Read [the design](Docs/Design.md) for contracts and [the plan](Docs/Plan.md) for
milestones and acceptance gates. Upstream references:
[style system](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIViews/SwiftTUIViews.docc/Style-System.md),
[theme model](https://github.com/SwiftTUI/swift-tui/blob/main/Sources/SwiftTUIPrimitives/Styling/Theme.swift).
