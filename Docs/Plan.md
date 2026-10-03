# Implementation plan and verification

The delivered slices are a runnable local dashboard and agent creation using
simulated agents. Accepted contracts and ownership live in [Design.md](Design.md);
commands and interaction instructions live in [the README](../README.md).

## Delivered slices

- One `Chio` library depending on the published `SwiftTUIViews` product; one
  `chio-dashboard` executable using the SwiftTUI runtime.
- Semantic theme values, a Charm-inspired default and a light customization,
  plus native GroupBox, List, TextField, Button, Picker, Toggle, and ProgressView styles.
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

## Verified on macOS

Swift 6.4, with SwiftTUI pinned at
`2d84ac7083993da2ef52e9d3d30255467efb9553`:

- `swift build --product chio-dashboard` passes.
- `swift build -c release --product chio-dashboard` also passes. Interactive
  launch instructions use release mode; debug enables extra upstream verification.
- 70 Swift Testing tests pass: 47 library tests and 23 dashboard tests, including
  parameterized widths, themes, progress values, sample scenarios, and form states.
  Evidence comprises a full 69-test run followed by the added parameterized form
  layout test (six size/theme cases); no behavior changed between those runs.
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
Use the supported `SWIFTTUI_DIAGNOSTICS` frame trace to investigate that next,
alongside terminal input-to-output timing, before adding caches or changing layout.

## Remaining boundaries

- The public API is experimental. Keep the SwiftTUI revision pinned while its
  style and focus contracts evolve; dependency upgrades need the hosted tests.
- Native list focus chrome is still owned by SwiftTUI's theme. Chio selection
  and authored content use Chio tokens; exact native focus palette customization
  requires an upstream public capability.
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
- The terminal smoke check used a pseudo-terminal, not every terminal emulator or
  assistive technology. Accessibility and color-capability coverage is partial.
- Linux execution and Static Linux SDK/musl linking remain unverified. Inspected
  upstream POSIX branches include Glibc paths without corresponding Musl paths;
  this is a source compatibility risk, not a demonstrated build failure here.
  A local tool inventory found no Linux container/VM runtime and no installed
  Swift SDK directory. No Linux build or execution was attempted. Source risks
  include terminal reads, detached process spawning, socket constants, and C math.

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
5. Evaluate Markdown through an AST and composed SwiftTUI views; choose a parser
   only when that slice is authorized.

No new products, renderer, general focus manager, or external agent integration
are required by these next decisions.
