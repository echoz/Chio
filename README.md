# Chio

**Beautiful terminal interfaces for Swift.**

*Chio* means attractive or pretty in Singlish. Chio is an opinionated, declarative
framework for polished terminal interfaces, built on [SwiftTUI](https://github.com/SwiftTUI/swift-tui).
Charm-inspired themes, searchable lists and checklists, form fields, file
selection, and Markdown compose with native SwiftTUI views. SwiftTUI handles
rendering, layout, input, and focus.

![Chio dashboard with selectable agents, status colors, progress, and keyboard hints](Docs/Media/dashboard.png)

[More screenshots and terminal recordings](Docs/Examples.md#gallery-and-recordings)

## Build with Chio

```swift
import SwiftTUI
import Chio

struct AgentsView: View {
    let agents: [Agent] // Your Identifiable model, with a stable ID and name.
    @State private var selection: Agent.ID?

    var body: some View {
        GroupBox("Agents") {
            SearchableList(agents, selection: $selection, searchText: \.name) {
                Text($0.name)
            }
        }
        .chioTheme(.default)
    }
}
```

One theme gives your controls consistent colors, spacing, and focus styling.
[API usage and recipes →](Docs/Usage.md)

## Try it

Requires **Swift 6.4+**, on **macOS 15+ or Linux**. From a repository checkout:

```sh
swift run -c release chio-dashboard
```

Use arrows to navigate, `/` to filter, Enter to open a report, **Ctrl-K** for the
command palette, and `q` to quit. Release mode gives better interactive performance.
For true-color terminals over SSH, prefix the command with `COLORTERM=truecolor`.

Add `--choices`, `--text-entry`, `--feedback`, or `--files` to try a focused example.
[Example controls and launch options →](Docs/Examples.md)

## Status

Chio is built primarily for personal use, with **Codex assistance and human
curation**. We cannot vouch for stability or production suitability; APIs and
behavior may change without notice. Component coverage is still growing.

## Documentation

- [API usage](Docs/Usage.md) — themes and component recipes
- [Examples](Docs/Examples.md) — controls, screenshots, and SSH guidance
- [Design](Docs/Design.md) — architecture and interaction contracts
- [Coverage and roadmap](Docs/Plan.md#component-coverage) · [Development checks](Docs/Plan.md#running-checks)

[MIT License](LICENSE).
