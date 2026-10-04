# Implementation plan and verification

The delivered slices are a runnable local dashboard, agent creation, Markdown
run reports, and a command palette using simulated agents. Accepted contracts and
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

## Verified on macOS

Swift 6.4, with SwiftTUI pinned at
`2d84ac7083993da2ef52e9d3d30255467efb9553`:

- `swift build --product chio-dashboard` passes.
- `swift build -c release --product chio-dashboard` also passes. Interactive
  launch instructions use release mode; debug enables extra upstream verification.
- 113 Swift Testing tests pass with explicit `--no-parallel`: 76 library tests and 37
  dashboard tests, including parameterized widths, themes, progress values,
  sample scenarios, forms, and reports. All existing regressions remain intact.
- The combined concurrent dashboard run hit frame-deadline failures across form,
  report, and palette suites. The serial run passes with the same assertions and
  deadlines; concurrent hosted-suite execution remains unverified. Use the
  explicit serial command in the README on this toolchain.
- Pure tests cover fuzzy ranking, Unicode matching, stable selection, and
  deterministic simulation transitions.
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

## Remaining boundaries

- The public API is experimental. Keep the SwiftTUI revision pinned while its
  style and focus contracts evolve; dependency upgrades need the hosted tests.
- Native list focus chrome is still owned by SwiftTUI's theme. Chio selection
  and authored content use Chio tokens; exact native focus palette customization
  requires an upstream public capability.
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
- Linux execution and Static Linux SDK/musl linking remain unverified. Inspected
  upstream POSIX branches include Glibc paths without corresponding Musl paths;
  this is a source compatibility risk, not a demonstrated build failure here.
  A local tool inventory found no Linux container/VM runtime and no installed
  Swift SDK directory. No Linux build or execution was attempted. Source risks
  include terminal reads, detached process spawning, socket constants, and C math.

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

## Next decisions after trying the dashboard

1. Gather visual and interaction feedback from running the binary at everyday
   terminal sizes in release mode. Profile typing and selection latency against
   the baseline above before adding more components.
2. Validate a Linux build and an actual static musl executable separately, against
   the pinned dependency. Keep failures visible rather than promising portability.
3. Investigate upstream public focus-theme integration and finite collection
   measurement before scaling the list to large datasets.
4. Try the Create agent workflow before broadening the form API. Additional field
   types and grouped forms should follow concrete application needs.
5. Try reports and horizontally scrolling tables at everyday terminal sizes before
   adding syntax highlighting, active links, or large-data table behavior.

No new products, renderer, general focus manager, or external agent integration
are required by these next decisions.
