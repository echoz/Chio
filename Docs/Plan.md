# Chio plan and verification

This document records shipped scope, verification policy, proposed work and
remaining boundaries. [Design](Design.md) owns architecture and behavior;
[Usage](Usage.md) owns API recipes; [Examples](Examples.md) owns launch commands
and controls. Earlier investigations and per-slice results remain in the
[v0.1.0 development record](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md)
and Git history.

## Current release

[Chio 0.1.0](https://github.com/echoz/Chio/releases/tag/v0.1.0) is the first
experimental source release, tagged at
`1bcc08ce23747c8c8b1121e3add3c37951f7b09e`. The agreed feature sequence is complete,
including the bounded diff prototype, theme previews and showcase verification.
This establishes the delivered workflows, not complete Charm feature parity or
production stability. Chio remains personal software built with Codex assistance
and human curation, under the MIT license.

The package requires Swift 6.4+, with macOS 15+ or Linux. All four direct
dependencies are revision-pinned. Consumers must therefore use a revision
requirement for Chio: `from: "0.1.0"` and `exact: "0.1.0"` are unsupported by the
current dependency graph. The release notes contain the tested installation
snippet using the immutable release SHA. A separate macOS consumer resolved,
compiled, linked and ran with the same dependency pins as the release.
Version-based consumption needs a separate dependency change and consumer checks.

No prebuilt binaries or fully static Linux executable are published.

## Component coverage

The following describes Chio 0.1.0 with SwiftTUI pinned at
`2d84ac7083993da2ef52e9d3d30255467efb9553`. Native controls own layout, state,
input, focus and scrolling. A styled control, a reusable interaction and an
example application are different scopes.

| Area | Delivered | Boundary |
| --- | --- | --- |
| Design system | Default, light and btop themes; semantic colors, spacing and treatments | Native focus/chrome and limited-color conversion have remaining limits |
| Groups and everyday controls | Styles for native groups, buttons, toggles, pickers, text fields, secure fields and multiline editors | No replacement controls, completion/history system or password-reveal API |
| Search and choices | `SearchableList`, `SearchableChecklist`, fuzzy/substring filtering, stable selection, checked membership, counts and empty messages | No bulk/range selection, async choice workflow or large-data performance claim |
| Forms | `FormField`, `FormValidation`, conditional and grouped examples with Save/Cancel | Applications own drafts, rules, first-invalid focus and submission; no form DSL, wizard or prompt runner |
| File selection | Async directory listing, search, extension/hidden-file policies, errors/retry and explicit confirmation of one readable regular file | No directory/multiple selection, save panel, root confinement or filesystem watching; confirmation does not reserve a file |
| Help and commands | `KeyHint`, wrapping `KeyHints`, `KeyboardHelp`, `StatusBar` and native command-palette styling | Descriptions do not register or execute commands; no notification/status queue |
| Feedback | Native progress, spinner, alert/confirmation and explicit toast styles | Native timing, presentation and dismissal; no Chio scheduler or general banner component |
| Navigation | Native tab, scroll and disclosure styles; checked `Pagination` and `PageControl` | Pagination requires finite totals; no tree adapter, tree-specific arrow routing or separate viewport engine |
| Tables | Themed native tables and Markdown table composition | Border/background chrome remains native; selected/sorted data-table workflows are not broadly validated |
| Markdown | Immutable parsed documents; headings, rich text, lists, quotes, code, rules and tables | Useful subset; unsupported content has readable fallbacks, not full Glamour equivalence |
| Code and links | Swift syntax highlighting, plain override, opt-in native links and `ChioLinkStyle` | Other languages stay plain; applications own destination policy/effects; no image renderer |
| Instrumentation | Passive `Sparkline`, border titles and measurement progress paint | One series; applications provide samples, retention, timing, units and thresholds |
| Duration display | `DurationText` | Timekeeping and expiry remain application-owned; no public stopwatch/countdown engine |

Installed styles are defined by
[`View+ChioTheme.swift`](../Sources/Chio/Presentation/View+ChioTheme.swift).
Do not infer support for every native control from `.chioTheme(...)` alone.
Behavioral contracts are in [Design](Design.md); component and example coverage
lives in [ChioTests](../Tests/ChioTests) and
[ChioDashboardTests](../Tests/ChioDashboardTests).

The dashboard, creation/report flow, grouped forms, metrics and review inbox are
compositions of these pieces. Application simulation, sorting and review state
remain in the example target. The diff reader proves bounded read-only
unified/split presentation and hunk navigation; it is not a public diff API,
editor, VCS integration or large-document solution.

## Proposed next slice: 2D maps

Planning proposal, 2026-10-08. The user wants world and street maps, vector input,
detail reduction and a minimum usable size in a flat 2D presentation. Research
supports a prototype; rendering quality, performance and dependency suitability
are not yet proved. This proposal adds no shipped API or implementation.

Build one composable map with themed geography, readable labels, locations and
route overlays. Keep source loading separate from presentation. The proposed
[design boundary](Design.md#geographic-maps-proposed) retains SwiftTUI's renderer,
layout, input and focus. The first usable deliverable is an **offline world and
street example using the same component**, not a world-only outline demo.

### 1. Prove the terminal rendering

Use a small Natural Earth world fixture and an attributed OSM-derived neighborhood
fixture containing roads, water, selected buildings and names. Record provenance,
source version/date, license and conversion steps. Start with bounded local
GeoJSON; no online service or API key is needed to judge the component.

Prototype projection, cell-aspect correction, lines, polygon fills/holes and
native text labels. Compare world and street detail at representative allocations
(100×30, 60×20 and 36×18 cells), with reported and estimated cell metrics. These
are test sizes, not promised minimums. Measure and choose the minimum usable
allocation for each view and its fallback. Check per-cell color priority and
legibility in default, light and btop themes before freezing a public API.

Exit: both maps are recognizable, useful detail survives reduction, small layouts
degrade deliberately, and recorded vertex counts, frame times, memory and terminal
output establish realistic budgets. If native drawing cannot support the result,
record the specific limitation before expanding the implementation scope.

### 2. Build the reusable offline component

Implement checked geography/camera values, bounded preparation and themed native
presentation within the existing Chio target. Follow existing responsibility
directories; add no package split or general map DSL. Pan/zoom, selected markers,
route overlays, prioritized labels and the below-minimum summary are the reusable
behavior. Applications supply features and own location meaning and route creation.
Resizing reflows detail while preserving camera and selection; theme changes
preserve interaction. Keyboard navigation must work without mouse reporting.

Exit: a runnable local example switches world/neighborhood fixtures and exercises
pan, zoom, selection, resizing and themes. Add model tests for checked decoding,
projection, latitude bounds, antimeridian crossing, clipping, holes and work limits;
raster tests for detail/label priority, color collisions and size fallbacks; hosted
tests for focus, authoritative bindings, batched input and resize transitions.
Test cancellation and rejection of stale preparation results with controlled work.

### 3. Verify and publish the first slice

Run the existing [verification gate](#running-checks), adding a bounded release
terminal workflow and the map regression suites without weakening existing checks.
Measure rapid pan/zoom against the budgets from the proof. Exercise macOS and
Linux separately; keep live Ghostty/Blink SSH appearance and latency evidence
distinct from local raster and PTY results. Verify estimated cell metrics and
limited-color readability without reopening the shelved color-detection work.

Update public usage, example commands and README inspiration credits. Add the
map component to the [showcase](#demo-site), including matching recordings,
three-theme previews and commands. Exit: verified implementation and published
example evidence; only then describe the offline map slice as delivered.

### Later proposal: vector tile loading

For arbitrary street exploration, evaluate MVT decoding plus a configurable tile
source. Map source layers into the demonstrated geographic model; tile-local
coordinates, layer identities and optional feature IDs are not global geography
or stable selection identities. Respect extent, buffered geometry and attribution.
Define missing/loading/failed tile behavior, bounded concurrency and cache sizes,
request cancellation, stale-result rejection and malformed/oversized input limits.
Keep deterministic fixture-backed tests and examples as the default.

This is a separate decision: live external-service examples remain deferred by
project policy. OpenFreeMap is a provider candidate, not a promised service or
default network dependency. PMTiles/MBTiles, offline downloads, geocoding and route
calculation are not required for the first slice.

### Evidence and dependency decisions

- [Natural Earth](https://www.naturalearthdata.com/downloads/) supplies generalized
  world vectors under [public-domain terms](https://www.naturalearthdata.com/about/terms-of-use/).
  It is not street data; OSM-derived fixtures retain their own attribution/license.
- [GeoJSON](https://www.rfc-editor.org/rfc/rfc7946.html) is the initial fixture
  interchange candidate. Support the geometry subset the examples actually use,
  with explicit rejection/fallback for unsupported input rather than a GIS framework.
- [MVT](https://github.com/mapbox/vector-tile-spec) defines tiled vectors;
  [OpenFreeMap](https://openfreemap.org/) is a possible OSM-derived source.
  [MVTTools](https://github.com/Outdooractive/mvt-tools) is a Swift decoder candidate;
  compare its dependency/build cost with a narrow adapter using
  [SwiftProtobuf](https://github.com/apple/swift-protobuf) before selecting a pin.
  Audit compression/system-library needs and run macOS/Linux consumer checks;
  neither library choice nor static-musl compatibility has been verified.
- [MapSCII](https://github.com/rastapasta/mapscii) is a terminal-map UX reference,
  not a dependency or API to port. The pinned native
  [Canvas API](https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIPrimitives/Draw/CanvasDrawing.swift)
  establishes available drawing operations, not map performance.

## Remaining scope audit

The map proposal above is the next design under consideration; there is no
committed broader component queue. Real application use remains useful validation.
Further hardening and a stable release are possible directions, not approved
numbered phases or completion promises.

Prioritize demonstrated regressions in shipped behavior: focus, selection,
editing, narrow layout, presentation, responsiveness and supported-platform
execution. Resolve defects at their owning layer. Changing the SwiftTUI pin or
shipping a fork requires a reproducible dependency decision and native/Chio
integration evidence; an ignored local patch is not a distribution strategy.

Public additions require a concrete consumer need and reusable UX value:

- Promote the diff prototype only after resolving source wrapping, large-input
  behavior and split-width policy with real usage evidence.
- Extract a general list/detail layout only if another consumer establishes a
  shared contract.
- Completion/history, async choices, wizards, broader file selection, tree
  adapters, status queues and more themes remain possible gaps, not tasks.
- Keep monitoring, clocks, workflow engines, annotations, persistence, external
  services and repository operations with applications.

Prove an accepted addition in a small runnable example, document actual public
APIs, retain relevant model/raster/hosted regressions, and run a release terminal
workflow. Visible changes also follow the [showcase workflow](#demo-site).

### btop-inspired UI inventory

The accepted btop-inspired work is delivered: a compact palette, optional border
headings, measurement meters and a passive history graph in `--metrics`.
Applications own sampling and interpretation. Dense sorting is demonstrated by
`--inbox`; it does not establish sortable table headers. Draggable split panes,
multiple graph series and additional glyph modes remain unproved. The original
[inventory](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#btop-inspired-ui-inventory)
records the reference audit and extraction rationale.

### gh-dash and Hunk UI inventory

The delivered inbox exercises dense collections, sorting, preview visibility and
reader focus through existing primitives. The diff prototype adds immutable local
fixtures, aligned gutters, explicit summaries and logical hunk navigation.
Neither promises product parity. GitHub requests, Git/JJ/Sapling ingestion,
editor launching, note storage and agent sessions are application concerns.
The original [reference audit](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#gh-dash-and-hunk-ui-inventory)
remains historical design evidence, not a build order.

## Running checks

With Swift 6.4 and Python 3 installed, run from the repository root:

```sh
bash Scripts/ci/verify.sh
```

The gate serializes builds and hosted tests. It runs all tests in release,
selected tests in debug, a standalone release build, 20 plain-text snapshots and
15 real pseudo-terminal workflows. Snapshot files are inspection artifacts;
Swift tests assert the rendering contracts.

The approved debug/release split keeps library controls, domain values, raster
layouts and focused examples in debug. `CreateAgentTests`, `DashboardPaletteTests`,
`AgentReportInteractionTests` and the selected inbox/diff composition interactions
listed in the script run only in release, because unoptimized rendering can
exceed their frame deadlines. Their assertions and five-second waits are
unchanged. This does not establish full debug composition performance or cover
those workflows' debug-only native checks.

For a full debug investigation or a release-only suite, keep hosted tests serial:

```sh
swift test --no-parallel
swift test -c release --no-parallel
```

To exercise an already-built binary:

```sh
python3 Scripts/ci/terminal-smoke.py .build/release/chio-dashboard
```

Pass an example flag such as `--choices`, `--inbox` or `--diff` for its workflow;
[verify.sh](../Scripts/ci/verify.sh) is the complete list. Terminal checks cover
input/output, raw mode, cursor/alternate-screen restoration and exact original
terminal attributes. They do not prove live SSH latency or every emulator's
appearance. Recheck responsiveness when editing or navigation paths change.

Dependency upgrades also require a paused dashboard comparison (`--paused`) under
`TERM=xterm-256color`, first without `COLORTERM`, then with `COLORTERM=truecolor`,
both without `NO_COLOR`. The indexed run exercises the actual terminal palette;
the true-color run must preserve authored RGB.

### Demo site

The [showcase](https://echoz.github.io/Chio/) serves twelve recordings and 36
three-theme previews from `Docs/Media`, using the pinned local asciinema player
in `Docs/Site`. Its upstream license remains with the vendored assets. Components
and compositions stay separate; each card identifies Chio APIs, native controls,
application-owned behavior, source, launch command and keyboard guide.

Each example retains its selected static-preview theme during navigation. The
command follows that choice; original recordings retain their recorded themes.
Playback is explicit, pauses when leaving a recording, and can return to the
selected preview. Fragment links/history, script-free previews/downloads and
missing-asset fallbacks remain supported. The build gives owned CSS/JavaScript
content-hashed names. The player's NPT-poster limitation is recorded alongside
the vendored assets.

Preview the deployable output locally:

```sh
bash Scripts/docs/build-site.sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory .build/site
```

The [Pages workflow](../.github/workflows/pages.yml) builds relevant pull requests
and deploys relevant `main` changes. Pull requests receive no deployment
permissions; assets are served from the site without a CDN or asciinema account.

Completing a visible example change includes updating the showcase:

1. Capture the affected recording/previews from the verified release binary,
   using only local demo data. Reuse unaffected captures.
2. End published clips on the final complete UI frame, before teardown or logs.
   Inspect the full session separately for diagnostics, clean exit and terminal
   restoration; trimming a recording does not fix or suppress runtime warnings.
3. Update captions, matching commands and guide/source links. Preserve the
   Codex-assisted development and personal-software statement.
4. Check site assembly, assets/links, playback, pause, forward/backward seeking,
   navigation, focus, a 390-pixel layout and missing-asset/script-free fallbacks.
5. Commit, deploy and verify the published result before declaring the slice
   complete. An internal change with no visible difference needs no new capture.

## Release verification

The following evidence applies to release commit `1bcc08c`. It replaces the
per-slice pending-check notes in the historical plan. It is evidence for that
revision and the exercised boundaries, not a stability guarantee.

<a id="verified-on-macos"></a>

### Platform verification

[CI run 37416306113](https://github.com/echoz/Chio/actions/runs/37416306113)
passes on both platforms:

| Platform | Reported selected debug tests | Reported release tests | Additional checks |
| --- | ---: | ---: | --- |
| macOS / Xcode 27 | 377 | 407 | Standalone release build, 20 snapshots, all 15 terminal workflows |
| Ubuntu 24.04 x86_64 / Swift 6.4.0 / glibc | 376 | 406 | Standalone release build, 20 snapshots, all 15 terminal workflows |

Each configuration records one skipped test: case-distinct filenames on the Mac's
case-insensitive filesystem; removal of file-read permission in the Linux
container. CI artifacts contain each platform's logs, two test XML reports and
20 snapshots. The full local macOS gate also passed; a separate consumer build
verified the revision-based installation path before publication.

Model checks cover immutable replacements, validation/decoding, filtering and
identity. Public raster and hosted sessions cover theme paint, compact layouts,
editing, selection, focus, scrolling, presentation, cancellation, retained-binding
authority and batched input. Theme-comparison checks cover all three palettes
and preserve the CLI startup defaults and `--light` alias.

### Showcase verification

[Pages run 37416306124](https://github.com/echoz/Chio/actions/runs/37416306124)
deployed the release's gallery. Published HTML, all 36 theme PNGs, all twelve
recordings and referenced CSS/JavaScript/favicon assets matched the local build
byte-for-byte. Headless Chromium passed theme/command synchronization, playback
and final frames, pause/resume, seeking, navigation/history, focus restoration,
390-pixel layout, missing/stale-image recovery and script-free fallback. A
published-page mobile check also passed theme changes and actual playback.

All 36 preview captures used the same initial application state per example and
explicit true-color output; each exited successfully and restored terminal
modes. Representative images were visually inspected. Choices, dashboard,
Markdown and inbox each emitted the known `collection.unboundedRealization`
warning once per theme after restoration. Those twelve warnings remain in full
capture evidence; selected frames and published clips contain no diagnostics.
Browser checks establish gallery behavior, not live Blink/SSH rendering.

### macOS toolchain findings

Some Apple Swift 6.4 toolchains do not discover the installed Swift Testing macro
plugin. `verify.sh` detects and supplies it when available; its command is the
preferred entry point. The attempted native backend could not find Testing.

Apple Swift `6.4.0.34.1` with Command Line Tools also emitted linker warnings for
nonexistent `CommandLineTools/Developer/usr/lib` and framework search paths.
An independent dependency-free package reproduced the warning and ran; Xcode 27
built that probe without it. This is recorded in
[SwiftPM issue #10557](https://github.com/swiftlang/swift-package-manager/issues/10557).
Chio adds no suppression flags and does not change the global developer selection.

### Responsiveness baseline

Use release mode for interactive examples: native debug verification adds
substantial layout cost. The historical dashboard probe at `2aba923` measured
median selection at 344 ms debug / 73 ms release and Name typing at 729 ms /
122 ms release. Later focused probes informed hint-layout reuse and smaller
native row compositions. These were small local samples including capture and
decoding overhead, not SSH timings, benchmarks of the current release or
large-data guarantees. Detailed measurements remain in the
[historical baseline](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#responsiveness-baseline).

## Linux and CI

[CI](../.github/workflows/ci.yml) runs on `main` pushes and pull requests using
Xcode 27 and the Swift 6.4.0 Ubuntu 24.04 container. Builds/tests serialize within
each job; artifacts retain logs, text captures and xUnit reports. The release's
x86_64/glibc result is recorded above. Earlier ARM64 Linux builds and terminal
checks passed for older slices; they are not full current-release ARM64 coverage.
Ordinary Linux executables need the Swift/Foundation runtime libraries.

Earlier CI failures led to lighter viewport/diff row composition, explicit
focus synchronization in fixtures and the approved release-only composition
checks. The current gate passes those exercised paths without extending their
deadlines. Historical failures are not an active defect queue; future failures
still require evidence and must not be hidden by weakened tests.

### Static Linux blocker

Static Linux remains blocked. A Swift 6.4.0 ARM64 cross-build with the matching
`swift-6.4.0-RELEASE_static-linux-0.1.0` SDK failed because upstream SwiftFiglet's
platform imports omit Musl, leaving POSIX symbols such as `access`, `opendir`
and `fopen` unavailable. Figlet is reached through Chio's library dependency,
not only the example. No static executable was produced.

[Run 37174543215](https://github.com/echoz/Chio/actions/runs/37174543215)
reproduced the blocker on x86_64. The manual
[static workflow](../.github/workflows/static-linux.yml) retains failures; if a
future build succeeds, it checks ELF dependencies and executes the terminal
workflow. Use the matching official open-source compiler/Static Linux SDK;
Apple's Xcode compiler is not a substitute.

Source inspection found additional Musl gaps in native math, terminal, image,
link, PTY and socket paths. These are audit findings, not later compiler
failures: compilation stopped at Figlet. Native termios code also contains
Darwin VMIN/VTIME tuple indices. Linux `cfmakeraw` supplies the tested path's
correct values, but passing restoration tests do not prove those indices portable.
One import fix alone cannot establish static support; a changed dependency needs
compiled, linked and executed evidence before a static-distribution claim.

## Remaining boundaries

These limits apply to the pinned implementation; none authorizes another
renderer, focus system or hidden dependency patch.

| Boundary | Current limit and responsible follow-up |
| --- | --- |
| Native style hooks | Table border/background chrome, list focus gutter, palette shell, prompt headers and disabled-editor glyph paint are not fully controlled by Chio. Keep native behavior and resolve missing hooks upstream. |
| Layout and lifecycle | Scroll focus reveal can move a two-axis viewport by one cell; nested tab strips can receive stale width proposals; expanded disclosure focus includes descendants. Keep the documented native contracts for [scrolling](Design.md#scrolling), [tabs](Design.md#tabs) and [disclosure](Design.md#expandable-groups-and-trees). |
| Choice composition | Changing choice fields inside `GeometryReader` triggered a native debug lifecycle-publication assertion. The full-window example uses `terminalSize`; arbitrary nesting remains unproved. |
| Collection measurement | Native ideal-size probes can realize all rows before a bounded viewport commits and emit deferred `collection.unboundedRealization` warnings. Small fixtures do not prove virtualization or large-dataset performance; diagnostics are retained. |
| Early input | Search, palette and form handoffs cover documented type-ahead/batched paths. Arbitrary multi-control input before presentation settles needs native support, not an application-built editor or focus graph. |
| Portability and accessibility | CI and pseudo-terminals cover specific workflows. Other distributions, architectures, assistive technologies and live SSH devices require separate evidence. Static Linux is blocked as above. |

### Proposed connected table grid correction

Two historical patches are archived in `v0.1.0` and **not applied to the default build**:
[SwiftTUI table paints](https://github.com/echoz/Chio/blob/v0.1.0/Patches/SwiftTUI-table-style-paints.patch) against the
pinned native revision, and [Chio connected grid](https://github.com/echoz/Chio/blob/v0.1.0/Patches/Chio-connected-table-grid.patch)
against `b47280b`. The combined preview passed local Chio tests and terminal paint
checks, but full upstream gates and API-inventory regeneration were not run.
Shipping it needs an upstream fix or an explicit reproducible dependency decision
and fresh integration evidence. The
[original investigation](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#proposed-connected-table-grid-correction)
records the candidate and its limits; an ignored preview binary is not shipped.

### Proposed ANSI-256 conversion correction

**Shelved.** The user closed this investigation on 2026-10-05: no SwiftTUI PR,
maintained fork, forced true-color default or Chio color-depth flag is planned.

Ghostty and Blink SSH reports lacked `COLORTERM`/`TERM_PROGRAM`; the pinned
detector selected ANSI16 for `xterm-ghostty` and ANSI256 for `xterm-256color`.
That missing remote metadata does not describe the terminal's actual RGB support.
The inspected SSH server accepted `LANG`/`LC_*`, not `COLORTERM`; no configuration
was changed. See [Colors over SSH](Examples.md#colors-over-ssh) for explicit
launch/forwarding options. PTY evidence verifies authored RGB with
`COLORTERM=truecolor` and suppression under `NO_COLOR`, not the final live-device
appearance. `--force-color` alone does not select true color.

Separately, the pinned indexed-color quantizer rounds onto a uniform cube and
ignores the grayscale ramp, washing out dark colors. The
[native conversion](https://github.com/echoz/Chio/blob/v0.1.0/Patches/SwiftTUI-ansi256-quantization.patch),
[consumer regression](https://github.com/echoz/Chio/blob/v0.1.0/Patches/Chio-ansi256-emission.patch) and
[upstream preparation](https://github.com/echoz/Chio/blob/v0.1.0/Patches/SwiftTUI-ansi256-upstream.md)
are unapplied experiments archived in `v0.1.0`. Focused probes passed, but full
native gates did not run; no upstream PR was published. Detailed algorithms,
compatibility exceptions and evidence
remain in the [shelved investigation](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#proposed-ansi-256-conversion-correction).
Reopening it requires a new dependency decision, not another automatic roadmap task.

### Markdown syntax highlighting

Swift highlighting uses pinned Tree-sitter 0.26.13 and tree-sitter-swift 0.7.4 C
targets, privately behind `MarkdownDocument`. They require no Swift wrapper,
JavaScript runtime or grammar generation. The grammar copies an unused query
bundle; Chio performs no query-resource I/O. [Design](Design.md#markdown-and-agent-reports)
owns source fidelity, budgets, plain fallback and theme contracts.

A prior SwiftSyntax 604.0.0 candidate crashed on deeply nested input despite
configured nesting limits, so it did not satisfy the plain-fallback contract.
The selected C integration passed macOS and glibc Linux checks. A local historical
probe measured roughly 1.40 ms versus 0.019 ms per document construction with
versus without classification, and about 4.56 MB additional unstripped executable
size. These are single-machine observations, not portable performance guarantees
or a clean-build comparison. The [dependency investigation](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#markdown-syntax-highlighting)
retains the full measurements and rejected alternatives. Static-musl support
remains blocked separately.
