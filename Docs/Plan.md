# Implementation plan and verification

The first slice is a runnable local dashboard using simulated agents. Accepted
contracts and ownership live in [Design.md](Design.md); commands and interaction
instructions live in [the README](../README.md).

## Delivered slice

- One `Chio` library depending on the published `SwiftTUIViews` product; one
  `chio-dashboard` executable using the SwiftTUI runtime.
- Semantic theme values, a Charm-inspired default and a light customization,
  plus native GroupBox, List, TextField, Button, and ProgressView styles.
- KeyHint, wrapping KeyHints, StatusBar, and searchable selection with fuzzy or
  substring filtering, stable IDs, result counts, and distinct empty states.
- Simulated running, completed, failed, paused, and empty states; theme switching;
  responsive layout and deterministic plain-text snapshot scenarios.
- Independent read-only review completed. Its focus/activation and snapshot-flag
  findings were fixed and verified before the initial commit.

## Verified on macOS

Swift 6.4, with SwiftTUI pinned at
`2d84ac7083993da2ef52e9d3d30255467efb9553`:

- `swift build --product chio-dashboard` passes.
- 42 Swift Testing tests pass: 36 library tests and 6 dashboard tests, including
  parameterized widths, themes, progress values, and sample scenarios.
- Pure tests cover fuzzy ranking, Unicode matching, stable selection, and
  deterministic simulation transitions.
- Public terminal-cell rendering checks cover theme colors, progress, wrapping
  by cell width, empty states, and complete layouts at 100 × 30, 100 × 26,
  100 × 24, 50 × 30, and 36 × 18.
- Public hosted-session tests cover Enter/Escape, arrows, Tab/Shift-Tab, internal
  and external query ownership, theme/resize preservation, and raw input batches
  `/q`, `/q\r\r`, `/zzz\r\r`, and `/\t` without intermediate frame waits.
- A real macOS pseudo-terminal smoke check covers launch, search text that
  includes `q`, Escape, theme switching, simulated failure, running to completion,
  empty-data toggling, and normal exit with terminal restoration.
  A temporary local web-host preview was also visually inspected; it is separate
  evidence from terminal execution.
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
- The terminal smoke check used a pseudo-terminal, not every terminal emulator or
  assistive technology. Accessibility and color-capability coverage is partial.
- Linux execution and Static Linux SDK/musl linking remain unverified. Inspected
  upstream POSIX branches include Glibc paths without corresponding Musl paths;
  this is a source compatibility risk, not a demonstrated build failure here.

## Next decisions after trying the dashboard

1. Gather visual and interaction feedback from running the binary at everyday
   terminal sizes. Refine this slice before adding more components.
2. Validate a Linux build and an actual static musl executable separately, against
   the pinned dependency. Keep failures visible rather than promising portability.
3. Investigate upstream public focus-theme integration and finite collection
   measurement before scaling the list to large datasets.
4. Evaluate forms through native controls, validation, help/error presentation,
   and first-invalid-field focus. Evaluate Markdown through an AST and composed
   SwiftTUI views; choose a parser only when that slice is authorized.

No new products, renderer, general focus manager, or external agent integration
are required by these next decisions.
