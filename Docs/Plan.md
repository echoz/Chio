# Implementation plan and verification

The delivered proof-of-concept slices are a runnable local dashboard, agent
creation, Markdown run reports, a command palette using simulated agents,
a focused searchable-choice form, native password/multiline text entry, and
confirmation with transient feedback.
They establish the design direction, not broad parity with Charm's components.
Accepted contracts and
ownership live in [Design.md](Design.md); commands and interaction instructions
live in [the README](../README.md).

## Delivered slices

- One `Chio` library depending on the published `SwiftTUIViews` product; one
  `chio-dashboard` executable using the SwiftTUI runtime.
- Semantic theme values, a Charm-inspired default and a light customization,
  plus native GroupBox, List, Table, TextField, Button, Picker, Toggle, and ProgressView styles.
- KeyHint, wrapping KeyHints, StatusBar, and searchable selection with fuzzy or
  substring filtering, stable IDs, result counts, and distinct empty states.
- Simulated running, completed, failed, paused, and empty states; theme switching;
  responsive layout and deterministic plain-text snapshot scenarios.
- Independent read-only review completed. Its focus/activation and snapshot-flag
  findings were fixed and verified before the initial commit.
- Create agent screen with native text entry, role selection, a conditional Test
  suite field, and Start immediately toggle. Creation adds and reveals the selected
  agent; cancellation restores the dashboard's query, selection, and native focus.
- Reusable FormField help/error presentation and FormValidation visibility state.
  Application-owned rules run at submission and the draft-to-agent boundary;
  failed submission focuses and reveals the first invalid field.
- Independent read-only form review completed. Its new-row visibility, narrow
  error visibility, and batched-submission findings were fixed and verified.
- Immutable MarkdownDocument values parsed with Swift Markdown 0.9.0, rendered
  by MarkdownView as themed native views. The slice includes headings, rich
  paragraphs, lists, quotes, code, rules, and readable unsupported-node fallbacks.
- Enter opens a selected agent's snapshot report. Native scrolling, persistent
  navigation hints, theme switching, and Escape restoration complete the reader.
  Creating and running a new agent leads to its own report without external services.
- Independent read-only Markdown review identified a one-row quote marker gap;
  a composed text marker fixes it. No private renderer or focus API is required.
- Native Markdown tables replace the text fallback, preserving column alignment,
  rich body cells, and native width/height measurement. The report includes a
  visible table example; horizontal scrolling keeps wide tables readable.
- ChioPaletteStyle for native command palettes, with fuzzy filtering, stable
  selection, disabled commands, compact rows, and theme-driven presentation.
  Ctrl-K opens the dashboard menu; native dismissal precedes report/form launch.
- Independent read-only palette review completed. Its rejected-query-write
  finding was fixed: selection follows the value retained by the application's
  query binding. Hosted tests also caught stale selection and palette reopening;
  synchronous search selection and resolved editor bindings cover those cases.
- Global and repository guidance audit completed before expanding component
  coverage. Markdown now reuses native column alignment, test fixtures use
  dedicated conformance extensions, and dashboard suites share a frame recorder.
  Independent review found no remaining issues in those corrections; that cleanup
  preserved native ownership, application-owned validation, and public APIs.
  The full serial suite (113 tests), release build, six snapshot captures, and
  terminal smoke check passed on macOS after the cleanup.
- Immutable domain and view-configuration values now use replacement operations.
  Theme customization uses `replacing(...)`; validation uses `recordingExit(from:)`
  and `submitting(_:)`, whose returned visibility state is assigned by the app.
  These replace the initial mutable APIs. Native control bindings update immutable
  drafts from their current bound value; simulation returns replacement agents.
  Running progress is restricted to finite `0..<1`, including through decoding.
  Hashing and coding are synthesized where their contracts fit, with the native
  type and snapshot exceptions recorded in [Design.md](Design.md#value-contracts).
  Independent review found no actionable issues. The full serial suite passes
  134 tests, including rejection paths and unchanged-original checks; native
  form/search/palette input and focus regressions retain their assertions.
  The release build, six snapshot captures, and real pseudo-terminal smoke check
  also pass on macOS for this refactor.
- Richer choice fields add `SearchableChecklist` with native multi-selection,
  explicit checks, search, counts, disabled-choice enforcement, and preserved
  hidden/removed membership. The `--choices` two-step example reuses
  `SearchableList` and `FormField` for language choice, then demonstrates
  app-owned one-through-three validation, current availability, and save/cancel.
  Independent review's repeated-activation and stale-success findings were fixed
  with scoped transitions, typed feedback, and hosted regressions; re-review
  found no remaining actionable issues.
  The integrated macOS run passes 158 tests, an optimized build, seven snapshot
  captures, and real pseudo-terminal workflows for both the dashboard and choices.
  Both workflows restore terminal modes and exit cleanly.
- Everyday text entry adds `ChioTextEditorStyle` and exercises native
  `SecureField` through the existing text-field style. The focused `--text-entry`
  example demonstrates masked editing, multiline notes, local validation,
  password clearing, cancel, and disabled input. Independent read-only review
  found no actionable issues. A full macOS run passed 169 tests; after making
  the empty editor fill its bounded viewport, all 12 text-entry checks passed
  again, including the new viewport regression. This covered 170
  tests at that slice (108 library and 62 dashboard/example), with existing assertions intact.
  The optimized build and all three real pseudo-terminal workflows pass, with
  exact terminal-mode restoration. Eight snapshot captures include the compact
  text-entry example; the full-size empty editor was also inspected.

- Confirmation and feedback add `ChioPromptStyle`, `ChioSpinnerStyle`, and
  explicit `ChioToastStyle`, plus the runnable `--feedback` publish/reset example.
  Native APIs retain modal focus, dismissal, timing, reduced motion and toast
  expiry. The independent review's state-binding ownership and clipped-header
  findings were fixed and covered by public hosted/raster regressions.
  The integrated macOS checks pass all 184 release tests, 162 selected debug
  tests, the production release build, nine snapshot captures and all four
  pseudo-terminal workflows, including clean terminal restoration. New Linux
  verification remains pending; the prior CI limitation is recorded below.

## Component coverage

Source audit at Chio `424f8e6`, using SwiftTUI revision
`2d84ac7083993da2ef52e9d3d30255467efb9553`. Charm's current component catalogs were
checked on 2026-10-03. This is a capability map, not a parity percentage: a basic
control, its styling, and a complete interaction workflow are different scopes.
Native API availability below is source evidence, not new Chio runtime evidence.
The verification sections describe the shipped paths that have actually run.

The reference scope is [Bubbles](https://github.com/charmbracelet/bubbles) for
interactive components, [Huh](https://github.com/charmbracelet/huh) for forms,
[Lip Gloss](https://github.com/charmbracelet/lipgloss) for presentation, and
[Glamour](https://github.com/charmbracelet/glamour) for documents.
[Charmtone](https://github.com/charmbracelet/x/tree/main/exp/charmtone) supplies
palette utilities; Chio ships its own semantic theme inspired by Huh rather than
depending on that Go package. Tabs, dialogs, banners, and command palettes also
come from Chio's original brief; they are not all standalone Bubbles packages.

### Design and input controls

| Capability | Chio today | Native foundation | Remaining work |
| --- | --- | --- | --- |
| Semantic themes | Delivered default/light palettes, tokens, spacing, and treatments | Environment and native style protocols | Broader control coverage; native focus colors and ANSI-256 conversion have upstream limits |
| Panels | Delivered through `ChioGroupBoxStyle` | `GroupBox` | Use the native name; SwiftTUI `Panel` means action scope, not a visual box |
| Buttons and toggles | Delivered themed controls; toggle interaction tested | `Button`, `Toggle` | More variants only when a workflow justifies them |
| Single-line input | Delivered `ChioTextFieldStyle`, search and form editing | `TextField` | No claim of a full enhanced-input suite such as completion/history |
| Password input | Native `SecureField` inherits Chio's text-field style; raster/semantic concealment, editing, submission and disabled behavior exercised | [SecureField][native-secure] projects masked text before styling | No reveal/mask configuration; application-authored metadata must not echo the password |
| Multiline input | `ChioTextEditorStyle` frames the native editor; paste, selection, wrapped caret movement, scroll reveal and theme/resize exercised | [TextEditor][native-editor] and `TextEditorStyle.editorContent` preserve native editing/scrolling | Disabled inner text color remains native placeholder paint; no completion/history/editor replacement |
| Compact single choice | Delivered one-row `ChioPickerStyle` with native arrows | `Picker`, `PickerStyle` | This is not a searchable dropdown or a rich option browser |
| Searchable single choice | `SearchableList` composed in `FormField`; `--choices` proves candidate/Next/Save/Cancel | [List][native-list] plus native editor | No separate single-choice wrapper or disabled-single-choice policy yet |
| Multiple choices | `SearchableChecklist`, visible checks/counts, retained hidden/removed IDs, disabled membership gate; app-owned limits and validation in `--choices` | Native `List` and `Table` accept `Binding<Set<ID>>` | No bulk select, range select, or pre-render source-freshness guarantee; source/eligibility inputs update with rendered views |
| Yes/no confirmation field | Styled native toggle is usable | `Toggle`, buttons | A distinct two-choice confirmation treatment, if needed; an action-confirmation dialog is a separate scope |
| Field help and validation | Delivered `FormField` and `FormValidation` visibility state | Bindings, submission and `FocusState` | Current rules, draft ownership and first-invalid focus remain app-owned |
| Conditional fields and dynamic choices | Conditional Test suite field demonstrated; native composition permits changing options | Result builders, state, `Picker`/`List` | Reusable asynchronous choice loading, stale-result policy and cross-field workflows are not delivered |
| Grouped forms and standalone prompts | One application form proves submission/cancellation | Native groups, sections, covers and focus | No Chio `Form`/`Section` DSL, paged wizard, prompt runner or Huh-style accessible prompt mode; add coordination only after concrete workflows |

### Collections, feedback and navigation

| Capability | Chio today | Native foundation | Remaining work |
| --- | --- | --- | --- |
| Searchable/selectable list | Delivered fuzzy/substring search, stable single selection, count, activation and two empty messages | [List][native-list] owns navigation and scrolling | No integrated pagination, loading/error/status workflow, multi-selection or demonstrated large-data performance |
| Tables | Delivered theme style and Markdown table composition; report navigation tested | [Table][native-table] owns grid, sizing, selection and navigation | Border/background paint correction remains unapplied; richer selected/sorted data-table workflows are not validated |
| Trees | No Chio tree workflow or style | [OutlineGroup][native-outline], `OutlineStyle`, separate `DisclosureGroup` | `OutlineGroup` expands all descendants and paints connectors with native colors; a collapsible tree needs composition, and exact connector color needs upstream support |
| File picker | No Chio file browser | No dedicated native picker found; lists, fields and scrolling are building blocks | Filesystem loading, navigation, allowed-item policy, errors and selection are genuinely missing reusable behavior |
| Pagination | No Chio paginator | Native views and input for presentation | Page arithmetic, navigation and compact display; scrolling is not pagination |
| Scrollable viewport | Used and tested in reports, tables and code blocks | [ScrollView][native-scroll], positions/readers/styles | Keep native scrolling; add a document-reader convenience only for demonstrated reusable UX |
| Progress/loading bar | Delivered determinate and indeterminate `ChioProgressViewStyle`, including reduced motion | `ProgressView` owns animation phase | Not a dedicated spinner; animated/gradient fill variants are not part of the current Chio scope |
| Spinner | Delivered `ChioSpinnerStyle` with semantic stage paint and native reduced motion | [Spinner][native-spinner], `SpinnerStyle`, presets/stages and native timing | Native braille cadence and stages; no Chio timer or frame catalog |
| Keyboard hints | Delivered manual `KeyHint` labels and wrapping `KeyHints` | Native key handlers/commands | Shared binding-to-help metadata and compact/expanded help are not delivered; the native registry's `KeyBinding` is not public |
| Status bar | Delivered composed `StatusBar` | Native layout/text | A footer is not a toast queue or reusable status-message workflow |
| Empty/status/banner views | Empty messages inside search; semantic statuses in the demo | Native text, layout and theme colors | Extract reusable presentation and actions when useful; no general empty-state/banner component yet |
| Toasts | Delivered explicit `ChioToastStyle` and local completion feedback | Native [.toast and ToastStyle][native-toast] handle presentation | Native expiry and explicit dismissal; no environment toast modifier or app notification queue |
| Alerts, confirmation dialogs and sheets | Delivered `ChioPromptStyle` for alerts and confirmation dialogs; native covers demonstrated | [Native presentation][native-presentation] and [PromptStyle][native-prompt] | Native focus and dismissal retained; header paint and arbitrary action wrapping remain native/app concerns; no Chio sheet style |
| Command palette | Delivered `ChioPaletteStyle`, filtering, disabled items and dashboard actions | Native action scopes, command registration and palette presentation | Surrounding palette chrome has an upstream styling limit; this is not a new Chio command system |
| Tabs | No Chio tab style or tested tabbed application | [TabView][native-tabs] and `TabViewStyle` | Style native selected/focused states and narrow overflow; no replacement tab controller |
| Timer and stopwatch | No reusable Chio component; demo simulation is not one | [TimelineView][native-timeline] and Swift clocks | Countdown/elapsed-time state, formatting and pause/resume behavior if demanded; keep scheduling native |

### Documents

| Capability | Chio today | Native foundation | Remaining work |
| --- | --- | --- | --- |
| Markdown documents | Delivered parsed immutable documents, headings, rich text, lists, quotes, fenced code, rules and tables | Swift Markdown AST becomes native `Text`, layout, `Table`, `ScrollView` | This is a useful subset, not complete Glamour feature equivalence |
| Syntax highlighting | Code is rendered literally with a language label | Native rich text can carry styled spans | Choose a suitable highlighter only after checking dependency/static-link cost; preserve whitespace and width semantics |
| Links and images | Destinations/alt text shown; no resource fetching or link activation | Native `Link`/rich text exists | Active links need explicit interaction/opening policy and terminal tests; image rendering is outside the present document scope |

The source of Chio's installed styles is
[`View+ChioTheme.swift`](../Sources/Chio/Presentation/View+ChioTheme.swift).
Reusable presentation lives in [`Sources/Chio/Presentation`](../Sources/Chio/Presentation),
and evidence in [`Tests/ChioTests`](../Tests/ChioTests) plus the dashboard tests.
Do not infer Chio support for every native control from `.chioTheme(...)` alone.

[native-secure]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Input/SecureField.swift
[native-editor]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Input/TextEditor.swift
[native-list]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Collections/List.swift
[native-table]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Collections/Table.swift
[native-outline]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Collections/OutlineViews.swift
[native-scroll]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/ScrollView/ScrollView.swift
[native-spinner]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Controls/Spinner.swift
[native-toast]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Presentation/ToastPresentation.swift
[native-presentation]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Presentation/PromptPresentationEntrypoints.swift
[native-prompt]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Presentation/PromptStyles.swift
[native-tabs]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/TabViews/TabView.swift
[native-timeline]: https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/Animation/TimelineView.swift

## Verified on macOS

Swift 6.4, with SwiftTUI pinned at
`2d84ac7083993da2ef52e9d3d30255467efb9553`:

- `swift build --product chio-dashboard` passes.
- `swift build -c release --product chio-dashboard` also passes. Interactive
  launch instructions use release mode; debug enables extra upstream verification.
- All 184 Swift Testing tests pass in release with explicit `--no-parallel`:
  120 library tests and 64 dashboard/example tests. The additional selected debug
  pass covers 162 tests with the same assertions and deadlines; the three larger
  dashboard workflow suites run in release, as documented below.
- Feedback checks exercise both native prompt kinds, custom colors, disabled and
  destructive actions, confirm/Cancel/Escape, one dismissal callback, exact editor
  focus restoration and resumed editing. The example changes theme, resizes an
  open prompt to 36 × 18, publishes, observes toast expiry and resets the result.
  Spinner raster checks cover stages and reduced-motion frames; toast tests cover
  all native tones, both themes, explicit and timed dismissal, editing beneath
  feedback, theme changes and resize. Timed lifecycle checks use bounded real
  hosted sessions, not a virtual clock or a proof of every scheduling interleaving.
- The combined concurrent dashboard run hit frame-deadline failures across form,
  report, and palette suites. The serial run passes with the same assertions and
  deadlines; concurrent hosted-suite execution remains unverified. Use the
  explicit serial command in the README on this toolchain.
- Pure tests cover fuzzy ranking, Unicode matching, stable selection, and
  deterministic simulation transitions. Immutable replacements preserve originals
  and unrelated fields; progress construction and decoding reject invalid fractions,
  spacing decoding rejects malformed values, and isolated exit tests retain
  constructor/replacement preconditions for theme spacing and glyphs.
- Choice tests cover native focus versus checked membership, Space/Return,
  filtered hidden checks, disabled and removed IDs, reordered/empty sources,
  rejected/transformed bindings, internal query retention, scroll reveal, and
  batched search handoff. A focused follow-up also starts on a native row, removes
  all options, and verifies recovery to search without losing checked IDs.
  The full form covers minimum/maximum/current-availability
  validation, successful and rejected Save, Back/Cancel, repeated activation,
  and continued native editing through theme and 36 × 18 resize. Raster cases
  exercise both themes at 100 × 30, 50 × 30, and 36 × 18.
- Text-entry tests verify enabled custom-color editor paint and visible disabled
  content in both themes. Synthetic password values stay out of rendered and
  semantic snapshots, including every hosted frame; secure nodes expose neither
  a control value nor text-query metadata. Native typing, deletion, secure paste
  filtering and Return submission remain intact. Multiline tests retain exact
  pasted line breaks, selection replacement, wrapped caret geometry, scroll
  reveal, and the editor's single Tab stop through theme/resize. Example tests
  cover first-invalid focus, password clearing, stale acceptance, locked controls,
  cancellation, and both themes at 100 × 30, 50 × 30, and 36 × 18.
- Public terminal-cell rendering checks cover theme colors, progress, wrapping
  by cell width, empty states, and complete layouts at 100 × 30, 100 × 26,
  100 × 24, 50 × 30, and 36 × 18.
- Public hosted-session tests cover Enter/Escape, arrows, Tab/Shift-Tab, internal
  and external query ownership, theme/resize preservation, and raw input batches
  `/q`, `/q\r\r`, `/zzz\r\r`, and `/\t` without intermediate frame waits.
- Form tests cover validation timing, conditional fields and native navigation,
  first-invalid focus and visible errors at 36 × 18, draft/focus retention through
  theme and resize, creation, duplicate submission, and cancellation restoration.
  Raw opening batches include `nq`, `n\t`, `nRelease\r\r`, repeated Ctrl-S after
  `nRelease`, and invalid `n\r`. Cell renders cover both themes at 100 × 30,
  50 × 30, and 36 × 18 with persistent actions and keyboard help.
- Markdown model/raster tests cover rich wrapping, Unicode, nested lists and
  quotes, literal punctuation, code whitespace, and readable fallbacks. Hosted
  code tests verify horizontal End/Home and theme-preserved offset and focus.
  Report tests cover vertical navigation, theme/resize retention, filtered-list
  focus restoration, created-agent runs, immutable snapshots, and raw Enter-q
  during presentation. Report chrome remains visible in both themes at
  100 × 30, 50 × 30, and 36 × 18. Independent review reports no remaining findings.
- Table tests cover parsed alignments, empty cells, header-only content, body
  emphasis/code, Unicode cell alignment, narrow clipping, following prose, and
  native table semantics. Both Chio themes and customized header colors are
  verified; native border-color limitations are recorded below. The strengthened
  hosted navigation regression passes in a focused rerun: Tab moves from the
  vertical reader to the table, End/Home scroll columns, theme/resize retain
  focus, and Shift-Tab returns to the reader so Down scrolls vertically.
- Palette tests cover customized colors in both themes, long-list selection
  visibility, current-query activation from batched input, disabled actions,
  empty results, initial type-ahead, resize, theme switching, and reopening.
  Report/form actions preserve exact native focus and filtering from both search
  and results. Filtering commits the application selection before palette actions;
  a rejected external query write cannot change selection for an unchanged query.
- A real macOS pseudo-terminal smoke check covers launch, search text that
  includes `q`, Escape, theme switching, simulated failure, running to completion,
  empty-data toggling, and normal exit with terminal restoration.
  A temporary local web-host preview was also visually inspected; it is separate
  evidence from terminal execution.
- A second real pseudo-terminal check covers opening Create agent, invalid
  submission, Name entry, native role arrows, the conditional Test suite field,
  Start immediately toggling, and successful creation. The new agent and suite
  appear in the dashboard, the footer remains visible, and `q` exits with code
  zero and restores the alternate screen. This checks terminal output and input,
  not the user's Blink device; the new form was not inspected in a browser.
- The report slice's release binary passes a real pseudo-terminal workflow:
  start a run, wait for completion, open its report, End/Home navigation, change
  theme without changing reading position, return to filtered results, and quit
  with exit code zero and alternate-screen restoration. Captured terminal text
  confirms the report hierarchy and persistent header/help. This remains local
  terminal evidence, not a live Blink-over-SSH or Linux check.
- The table release check confirms the header and all three illustrative rows
  appear near the report's top, theme switching retains the table, Tab/Shift-Tab
  returns to vertical reading, End reaches the report's end, and quitting restores
  the terminal with exit code zero. Captured terminal text was inspected.
- The palette release binary passes a local pseudo-terminal workflow: open a
  report, reopen into agent creation, edit and cancel, change theme, filter to no
  commands, and return to editing the original dashboard search. Normal quit
  restores the alternate screen with exit code zero. Captured terminal text was
  inspected; this is not a live Blink-over-SSH check.
- A separate macOS pseudo-terminal comparison reproduced the SSH color issue:
  with `TERM=xterm-256color` and no `COLORTERM`, the default surface emits
  `48;5;59` (gray). Adding `COLORTERM=truecolor` emits `48;2;33;29;42` (the authored
  dark plum). Both runs exited normally and restored the alternate screen.
  This proves emission, not final rendering on the user's Blink device.
- Public `TerminalHost` emission regressions preserve the default foreground and
  background RGB under the documented true-color environment and verify that
  `NO_COLOR` still suppresses color. These capture bytes through a pipe without
  taking ownership of a real terminal or using upstream testing SPI.

The installed Command Line Tools' default SwiftPM backend does not discover its
Swift Testing macro plugin automatically. The complete test run used the explicit
plugin flag documented in the README. The native backend was also attempted but
could not find the Testing module. Neither workaround changes package sources or
adds a runtime dependency.

## Responsiveness baseline

Local measurements of commit `2aba923` used a 100 × 30 pseudo-terminal,
`COLORTERM=truecolor`, and `--paused`, with no concurrent build or diagnostic
overrides. The same script injected individual keys and reconstructed terminal
text until the list selection marker or typed Name value became visible.

| Interaction | Debug | Release |
| --- | ---: | ---: |
| Selection change, median of six keys | 344 ms | 73 ms |
| Name typing, median of six characters | 729 ms | 122 ms |
| Open form, one observation | 1,215 ms | 208 ms |

These are small local samples, including capture/decoding overhead, with no SSH
transit or Blink display time. Both binaries exited normally. Release materially
improves responsiveness, but typing remains noticeable locally; this does not
establish which render phase dominates or promise performance on another host.
The supported `SWIFTTUI_DIAGNOSTICS` trace attributes roughly 72–74% of measured
pipeline time to placement, with no focus-sync convergence passes on these inputs.
Chio's hint flow now supplies native measurement and placement reuse signatures
containing its sole layout value, the gap. SwiftTUI still validates child inputs
and proposals. In the instrumented comparison, median typing changed from about
123 ms to 104 ms and 108 ms in two repeats; custom child measurement requests per
typing frame fell from 77 to 35. Selection timing did not consistently improve.
Hosted regression coverage changes labels, adds/removes hints, changes the gap,
and resizes through wrapping boundaries. Further placement profiling remains
useful; this bounded change does not resolve all latency.

The integrated Markdown/report release was rechecked with the original local
harness and no diagnostic overrides: median selection was 74 ms, median Name
typing was 103 ms (six inputs each), and opening the form took 206 ms. These small
samples show no evident regression from report presentation; SSH and device
display latency are still outside this measurement.

The command-palette release was checked with the same harness, with no concurrent
build or tests: selection measured 75 ms median and Name typing 92 ms median
(six inputs each), with one form opening at 215 ms. These local samples show no
evident responsiveness regression; they do not include SSH or device latency.

The richer-choice release was sampled at 100 × 30 with no concurrent build or
tests. The checklist measured 28 ms median for search typing, 45 ms for row
navigation, and 67 ms for toggling (six inputs each). The original dashboard
harness measured 99 ms for selection and 108 ms for Name typing, with one form
opening at 239 ms. Dashboard samples are slower than the earlier palette sample;
these runs do not isolate a cause or establish a regression-free result. The
dashboard retains its original application/view entry structure; `--choices`
uses a separate native App in the same executable. All timings include local
capture/decoding overhead and exclude SSH and device display latency.

The text-entry release was sampled at 100 × 30 with no concurrent build or tests:
masked typing measured 55 ms median and multiline typing 61 ms median, with six
characters each. These are local observations including capture/decoding overhead;
they do not measure SSH transport or Blink display latency.

## Linux and CI

The initial demonstration slices are delivered. Portability verification adds CI and
repeatable terminal checks without changing the public API or dependency pins.

- Ubuntu 24.04 ARM64, official `swift:6.4.0-noble` container: all 113 tests pass
  with `--no-parallel` (76 library and 37 dashboard). The debug and release
  dashboard builds pass. The tested release is a dynamically linked glibc ELF
  executable requiring Swift/Foundation runtime libraries, not a static artifact.
- The committed `Scripts/ci/terminal-smoke.py` passes on macOS ARM64 and Linux
  ARM64 release builds. It checks canonical mode/echo disabled, VMIN=1/VTIME=0,
  real typed search, palette no matches and cancellation, restored search focus,
  report/table opening, form entry/cancellation, zero exit, alternate-screen
  teardown, and exact restoration of the original terminal attributes.
- `.github/workflows/ci.yml` runs serial tests, an optimized build, snapshot
  captures, and that smoke check for macOS/Xcode 27 and Ubuntu 24.04/Swift 6.4.0.
  Logs and text captures are retained as CI artifacts. Snapshot captures are
  inspection artifacts; the Swift tests assert rendering contracts. macOS uses
  the currently available `xcode-27` preview runner because the package needs
  Swift 6.4.
- [Hosted CI run 37174523755](https://github.com/echoz/Chio/actions/runs/37174523755)
  passed for commit `297bacb` on macOS ARM64 and Linux x86_64. Each job passed
  all 113 tests, the release build, and the terminal smoke check. Both uploaded
  their full verification log and six snapshot captures; the artifacts were
  downloaded and checked. This adds x86_64/glibc execution evidence to the local
  ARM64 Linux run, without extending coverage to other distributions or devices.
- The workflows and scripts received an independent read-only correctness review
  with no actionable findings. Builds/tests remain serialized within each job.
- [Run 37183707010](https://github.com/echoz/Chio/actions/runs/37183707010) for the
  immutable-value commit `dcb0eb2` passed all 134 tests, the release build, and
  terminal smoke check on Linux x86_64. Its macOS job failed two existing
  Create-agent opening checks: the form rendered but Name had not acquired native
  focus before the deadline. Other openings passed; the log does not establish
  whether acquisition was lost or merely late. Local macOS verification passed.
  Keep the focus assertions and deadlines intact and distinguish fresh-run evidence
  from a demonstrated fix for this platform discrepancy.
- [Run 37186814418](https://github.com/echoz/Chio/actions/runs/37186814418) for the
  choice-field commit `b46228c` passed all 102 library tests on both platforms,
  including the new checklist. Its dashboard run failed with 13 issues on Linux
  and one on macOS, involving existing form-arrival focus and report/palette
  handoff checks. New choice-example checks passed. Some individual issue details
  were missing from both the streamed logs and retained artifacts. Targeted local
  reruns of initial/invalid form arrival and both palette handoffs passed unchanged;
  this does not establish a fix. CI now retains Swift Testing's xUnit report as
  well as console logs to improve evidence on subsequent failures. Assertions,
  deadlines, dependency pins, and the original dashboard remain unchanged.
- [Run 37210474889](https://github.com/echoz/Chio/actions/runs/37210474889) for
  text entry (`aae078e`) passed all 170 tests, the optimized build, eight snapshots,
  and three terminal checks on macOS. Linux passed all 108 library tests but
  reported 11 failures in the older dashboard form/report/palette workflows.
  The new choice and text-entry workflows passed on both platforms.
- Local x86_64 Linux reproduction under Rosetta established a debug timing
  failure matching the retained CI frames. The form's arrival callback executed,
  and Name received focus after about 5.4 seconds, beyond the unchanged five-second
  wait. Both palette commands also executed and eventually presented reports.
  Public runtime diagnostics reported only the already-known collection warning;
  the reproduction did not establish a lost callback or state write. An unchanged
  Linux ARM64 run passed the 13 targeted tests. These are platform/configuration
  observations, not a live SSH latency measurement.
- Verification now runs every suite in release mode, retaining the same assertions
  and deadlines against the optimized runtime. The additional debug pass includes
  library controls, domain values, raster layouts, and the focused examples; only
  `CreateAgentTests`, `DashboardPaletteTests`, and `AgentReportInteractionTests`
  run exclusively in release. This retains their behavioral coverage but does
  not cover their native debug-only lifecycle/layout traps or debug soundness
  sampling. Full debug investigation remains available with
  `swift test --no-parallel`. Separate xUnit artifacts identify each configuration.

- [Run 37213492012](https://github.com/echoz/Chio/actions/runs/37213492012) for
  `9ff6aff` passed macOS verification. Linux passed the selected debug tests, the
  full release suite, optimized build, and dashboard terminal smoke, then failed
  the existing choices terminal workflow at the batched Return transition from
  language to capabilities. The screen retained the filtered Rust row. This
  predates the feedback slice; its hosted regression passed, so the PTY failure
  remains open rather than being described as a fully green Linux run.

### Static Linux blocker

An actual ARM64 release cross-build using the official Swift 6.4.0 compiler and
matching Static Linux SDK `swift-6.4.0-RELEASE_static-linux-0.1.0` fails against
the unchanged published pins. The SDK archive checksum was verified before use.
SwiftTUI's `Vendor/swift-figlet/Sources/SwiftFiglet/SwiftFiglet.swift` imports Darwin,
Glibc, Android, or CRT but not Musl. Compilation fails at line 1771 onward with
missing `access`, `F_OK`, `opendir`, `fopen`, `getenv`, and related POSIX symbols.
Figlet is also reached through Chio's library dependency, not only the dashboard.
No static executable was produced; static linkage and execution are unverified.

The source audit identifies additional Musl gaps in upstream C math imports,
`PlatformMath`, terminal input/control guards, link opening, image file I/O,
platform/PTY adapters, and web socket constants. Those are inspection findings,
not subsequent compiler failures: the build stopped at Figlet. Correcting one
import would not establish full static compatibility. Upstream POSIX support
should be fixed and verified before changing Chio's dependency pin.

The manual `.github/workflows/static-linux.yml` reproduces the build attempt for
x86_64, retaining failures as artifacts. [Run 37174543215](https://github.com/echoz/Chio/actions/runs/37174543215)
failed at the same Figlet symbols and successfully uploaded its diagnostic log.
If compilation succeeds in the future,
it rejects an ELF interpreter/shared-library dependency and executes the same
terminal smoke check. It does not rewrite dependency sources or mask failures.
Use the [official Static Linux SDK instructions](https://www.swift.org/documentation/articles/static-linux-getting-started.html)
with the matching open-source toolchain; Apple's Xcode toolchain is not suitable.

The audit also found hard-coded Darwin VMIN/VTIME tuple indices in upstream
`TerminalPOSIXController.swift`. Linux's `cfmakeraw` supplies the intended values
for the tested path: the Linux PTY check observes VMIN=1/VTIME=0, functioning
input, and complete termios restoration. This is not proof those indices are
portable; correcting the platform implementation remains upstream work.

## Remaining boundaries

- The public API is experimental. Keep the SwiftTUI revision pinned while its
  style and focus contracts evolve; dependency upgrades need the hosted tests.
- The full-window choice example reads public `terminalSize` for its responsive
  decisions. Nesting its changing fields under `GeometryReader` triggered the
  pinned runtime's debug lifecycle-publication assertion for a missing
  `SearchableList.onAppear` handler. Explicit step identity alone did not fix it.
  The full-window composition passes the workflow without disabling checks;
  the upstream root cause and support for the original composition remain unproved.
  Checklist handlers capture the resolved native namespace during body evaluation,
  so deferred input uses the same scope as the rendered list.
- Native list focus chrome is still owned by SwiftTUI's theme. Chio selection
  and authored content use Chio tokens; exact native focus palette customization
  requires an upstream public capability.
- Native multiline editing samples enabled foreground from its surrounding
  environment before calling `TextEditorStyle`. The custom-color probe verifies
  that `.chioTheme` reaches enabled glyphs, surface, and border. Disabled inner
  glyphs use upstream placeholder paint and opacity; a modifier inside the style
  cannot replace that sampled paint. Chio keeps the protected native slot and
  avoids compounding its dimming. Secure controls omit value/text-query metadata
  from public snapshots; this does not sanitize app-authored labels or feedback.
- Native Table's generated control chrome masks `TableStylePresentation.borderStyle`.
  The Chio table style's header colors work, but borders/background chrome remain
  native upstream colors. Native headers also accept plain strings only; body
  cells preserve rich Text. Neither limitation is hidden by a second renderer.
- The pinned ANSI-256 quantizer rounds RGB channels onto uniformly spaced cube
  coordinates, although the terminal cube is nonuniform, and ignores its grayscale
  ramp. This washes out dark colors. True-color launch guidance is in the README;
  actual 256-color fallback remains an upstream defect. For dependency upgrades,
  compare the paused dashboard with `TERM=xterm-256color`, first without
  `COLORTERM`, then with `COLORTERM=truecolor` (and without `NO_COLOR`). The latter
  must preserve authored RGB; an eventual upstream fix should improve the former.
- Native measurement can report `collection.unboundedRealization` for the four
  demo rows. Large-dataset performance and virtualization remain unverified.
- Type-ahead during slash-to-search focus handoff appends to the query until the
  native editor acquires focus. Chio does not implement an editor, event loop,
  layout engine, or focus graph.
- Native full-screen presentation also drains input before its first frame. The
  demo covers simple Name type-ahead, an initial Tab, and valid/invalid submission
  during that handoff. Arbitrary multi-control navigation within the same opening
  input batch remains unsupported; a general solution belongs in SwiftTUI.
- Palette opening carries simple text/backspace until native editing owns focus.
  Navigation and Return before that first frame are consumed. The surrounding
  dropdown chrome remains native; the pinned `sheetStyle` does not control it.
- The terminal smoke check used a pseudo-terminal, not every terminal emulator or
  assistive technology. Accessibility and color-capability coverage is partial.
- Linux/glibc ARM64 and x86_64 tests and terminal execution pass. Static Linux/musl
  compilation is blocked by the pinned SwiftTUI dependency, as recorded above.
  Other distributions, architectures, and live SSH devices need separate evidence.

## Proposed connected table grid correction

The Blink screenshot exposed native black fills between Chio-colored table rows
and a border color too faint to read as a connected grid. A scoped terminal
appearance override fixed the fills but left native borders faint, so it was
not retained. The responsible fix is a small SwiftTUI style correction.

Two reviewable patches are retained, but are **not applied to the default build**:

- [SwiftTUI table paints](../Patches/SwiftTUI-table-style-paints.patch), against
  `2d84ac7083993da2ef52e9d3d30255467efb9553`, makes explicit border paint take
  precedence and adds an optional background paint. Nil retains native control
  colors; native selection, disabled opacity, geometry, and scrolling remain.
- [Chio connected grid](../Patches/Chio-connected-table-grid.patch), against
  `b47280b`, uses one surface for header, rows, and rules, with the exact semantic
  border color. It includes black-host regressions for every native box glyph,
  both themes, and custom colors.

The combined candidate passed all 104 Chio tests (74 library, 30 dashboard),
including native table navigation through theme and resize. Independent review
found no paint/state/reuse defects. A release build and pseudo-terminal workflow
also passed: all 176 visible grid glyphs emitted the exact theme border/surface
RGB in each theme, with scrolling, report return, and clean terminal restoration.
This is local terminal evidence, not a new live Blink-over-SSH check.

The locally built preview is `.build/previews/chio-dashboard-table-grid`; it is
an ignored build artifact, not the default dependency or a portable distribution.
Run it from the repository with `COLORTERM=truecolor` to inspect the report.

SwiftTUI's new focused tests were reviewed
but not run; its generated public API inventory must still be regenerated.
The required `swiftly` and `bun` tools are unavailable here, and its external
development companion could not be retrieved. Full upstream gates remain open.

Shipping this correction requires choosing a reproducible patched SwiftTUI
dependency or receiving the fix upstream. Chio's published-source pin remains
unchanged; a local SwiftPM edit is only integration evidence, not distribution.

## Next component slices

The coverage audit is complete and the following order is approved. The first
three slices are implemented; subsequent slices remain planned. Their public APIs remain
open to evidence from focused examples. Broaden reusable component coverage
before treating the framework as ready for release preparation.

1. **Richer choice fields — implemented.** Prove searchable single-choice form composition and
   a choose-many workflow using native `List` selection. Reuse `SearchableList`
   and `FormField` where they already fit; choose a new public abstraction only
   where the combined behavior earns it. Define stable IDs, checked membership
   versus keyboard focus, filtering that preserves checked hidden items,
   removed/disabled options, selection limits and validation. With native row
   focus, Space/Return toggle multi-selection; at container focus, Return routes
   to activation while Space toggles. Define activation/commit for both routes.
   A focused example
   should select multiple capabilities, filter away and back, and show errors.
   Acceptance: empty/no-match states, externally changed options/bindings, native
   navigation, theme/resize preservation, and usable narrow layouts. This is the
   highest-value behavioral gap after the current single-selection slice.
2. **Complete everyday text entry — implemented.** Exercise native `SecureField` under the
   existing style and add a native `TextEditorStyle` for multiline input. First
   render a small custom-color editor probe to establish how much of the inner
   text appearance can be controlled; record an upstream gap if necessary.
   Acceptance: passwords never appear in captured display/semantic output intended
   to conceal them, native editing and submission remain intact, multiline paste,
   wrapping/caret/scrolling work, and disabled/focused states remain readable in
   both themes. Use synthetic secrets in fixtures; do not invent an editor or
   promise reveal/mask configuration absent from native public APIs.
3. **Confirmation and feedback — implemented.** Add a coherent prompt treatment and spinner
   style, followed by native toast styling as the example needs feedback. Prove
   confirm/cancel, return of focus, disabled/destructive actions, narrow prompts,
   reduced motion and transient-message lifecycle. Pass toast styles through its
   explicit native API. Theme limitations in prompt headers remain visible.
4. **File selection.** Build one reusable file-choice workflow with application
   bindings and an owned filesystem-loading boundary. Specify files versus
   directories, filtering, path/symlink policy, loading/errors and confirmation
   before implementation. Prove navigation, empty/inaccessible directories,
   stale loads, cancellation and selection with deterministic temporary trees.
   Native lists, focus, input and scrolling remain responsible for interaction.

Further candidates are shared shortcut/help presentation, tabs and scroll styles,
expandable trees, page controls, richer grouped forms, and timer/stopwatch
presentation. Markdown highlighting and active links are separate document
capabilities with dependency and interaction decisions. These are open coverage
items, not completed work and not an instruction to build every candidate.

Each family should have a small focused example that a consumer can run directly,
public usage documentation, relevant model/raster/hosted-input regressions, and a
release terminal check. Keep the dashboard as an integration example. A component
counts as delivered only for its documented and exercised scope; inheritance of
an upstream API or a themed static screenshot is insufficient evidence of all
interaction behavior. Recheck responsiveness when editing/navigation paths change.

Existing upstream integration work remains separate: table paint correction,
native focus-theme control, ANSI-256 conversion, and finite collection measurement.
Keep large-data behavior unclaimed until measured. Resolve Musl support before
promising static Linux distribution; it does not block ordinary glibc components.
No new public products, renderer, general focus manager or external agent
integration are required by this roadmap.
