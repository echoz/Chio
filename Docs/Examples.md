# Runnable examples

[Back to Chio](../README.md) · [API usage](Usage.md)

Run these commands from a checkout of the repository. All examples are local;
the dashboard simulates agents, while file selection reads your filesystem.

## Dashboard

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
Static Linux distribution is a [separate compatibility check](Plan.md#static-linux-blocker).

## Choice fields

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

## Text entry

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

See [text-entry composition](Usage.md#text-entry) for the Swift API.

## Confirmation and feedback

```sh
COLORTERM=truecolor swift run -c release chio-dashboard --feedback
```

Press Publish (or Ctrl-P), then Tab to Cancel or Publish and press Return.
Escape dismisses the prompt. A local simulated publish shows the native spinner,
then a success toast that expires after three seconds. Discard (Ctrl-D) becomes
available after completion and opens a destructive confirmation. On the main screen, Ctrl-T changes
theme and Ctrl-Q quits. Nothing is sent or persisted. The example fits 36 × 18;
`--feedback --snapshot` captures its initial state without a terminal.

See [prompt and toast styling](Usage.md#confirmation-and-feedback) for the Swift API.

## File selection

```sh
COLORTERM=truecolor swift run -c release chio-dashboard --files
# Or start in a particular folder:
COLORTERM=truecolor swift run -c release chio-dashboard --files --directory ./Sources
```

Use arrows to select, `/` to filter names in the current folder, and Return to
enter a folder or choose a file. Parent or Backspace at results moves up. Escape
clears the filter; Cancel or Ctrl-G cancels without replacing a previous choice.
Ctrl-O reopens after a result, Ctrl-T changes theme, and Ctrl-Q quits.
The example reads directory metadata and displays the chosen path; it does not
open file contents or modify files. `--files` requires an interactive session
and does not support `--snapshot`.

See [file-selection options](Usage.md#file-selection) for bindings and filtering policies.

## Keyboard help

```sh
COLORTERM=truecolor swift run -c release chio-dashboard --keyboard-help
```

Browse with the arrows and press `?` for grouped shortcuts. `/` enters search;
typing `?` there edits the query. F1 opens the full reference from any control,
including search. `?` shows the shortcuts for the current browsing/action context.
Tab focuses the native help viewport or Close button; arrows, Page Up/Down and
Home/End scroll the viewport.
Escape closes help and restores the control you were using, retaining the filter
and selected agent.

Run, Return on a selected agent, or Ctrl-R increments a local counter. An empty
result set disables Run and omits it from expanded help. Ctrl-T switches theme,
and Ctrl-Q quits. Try resizing with help open: the example fits 36 × 18.
`--keyboard-help --snapshot` captures the initial browser state.

See [expanded keyboard help](Usage.md#expanded-keyboard-help) for the shared
descriptions and native presentation.

## Colors over SSH

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

## Gallery and recordings

[Watch the recordings in your browser](https://echoz.github.io/Chio/), with pause,
seeking, and fullscreen playback. These are recorded examples; run the binary to
interact with the controls yourself.

![Chio's dark dashboard with selectable agents, semantic status colors, progress, and keyboard hints](Media/dashboard.png)

The local agent dashboard combines native controls with Chio's theme, searchable
selection, progress styling, and contextual help.
[Watch](https://echoz.github.io/Chio/#dashboard) · [Download recording](Media/dashboard.cast).

### Searchable choices and light-theme feedback

![A searchable checklist with Build and Test checked, native focus on Test, and Deploy marked unavailable](Media/choices.png)

Checked membership stays distinct from keyboard focus. Filtering can hide a
checked item without removing it from the application's selection.
[Watch](https://echoz.github.io/Chio/#choices) · [Download recording](Media/choices.cast).

![Chio's light-theme feedback example with an accent outline around the focused Publish button](Media/feedback-light.png)

The same semantic theme roles apply to the light palette. Focused buttons use an
accent outline and preserve the surrounding surface.
[Watch](https://echoz.github.io/Chio/#feedback) · [Download recording](Media/feedback-light.cast).

These previews render real release-binary terminal output. Font rendering can
vary between terminals. The accompanying Asciinema-compatible recordings replay
locally after cloning the repository:

```sh
asciinema play Docs/Media/choices.cast
```
