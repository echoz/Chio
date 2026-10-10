# Chio verification

Current requirements for implementation, dependency and visible example changes.
[Plan](Plan.md) tracks active work; [release records](Releases/0.1.0.md) preserve
revision-specific results. For documentation-only changes, check links, anchors
and preservation of current contracts.

## Shared engineering rules

Chio pins [EngineeringRules v0.1.2](https://github.com/echoz/EngineeringRules/releases/tag/v0.1.2)
(`b2b8e8046fde8a482be7ae7e7ded72befd1e8d97`) through
[.swift-rules.json](../.swift-rules.json). This is a required local development
gate alongside the compiler, tests and platform checks below. It is not a package
dependency or a guarantee of purity, correct enum policy or API compatibility.

Install the pinned tool from its repository using its README. On this Mac, run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ~/.local/bin/swift-rules check --root .
```

Full Xcode supplies the required Swift/SourceKit. On Linux, omit `DEVELOPER_DIR`
and follow the pinned tool's Swift 6.4 and Ubuntu Noble requirements. The normal
check does not install tools or edit source, configuration or baselines; a missing
pinned installation is a failed prerequisite.

The gate scans all retained Swift files in `Sources`, `Examples` and `Tests`,
with no path exclusions and explicit target import allowlists. Its production
layout and file-scope checks apply to `Sources`. The component-first move is
pending shared-tool support: v0.1.2 rejects the new layout and does not select
its nested `Domain` groups for immutability and direct-effect checks. Keep the
existing pin until a reviewed stable release supports an explicit `Chio` target
opt-in; passing that gate with restored domain coverage is required before merging
the move. Do not suppress these findings or add baseline allowances. In v0.1.2 those production rules cannot
target `Examples`, whose syntax, constructors, ternaries, imports and selected
SwiftLint rules are still checked. Tests receive the latter checks too. Extend
the configuration when introducing retained source roots such as new spikes;
empty local directories and `Package.swift` are not scanned by this version.

The initial [.swift-rules-baseline.json](../.swift-rules-baseline.json) records
reviewed existing findings, with exact paths, source anchors and occurrence counts:

- Older test-fixture constructor shorthand is adoption debt. Replace it with
  concrete types when changing the owning suite, then prune the fixed entries.
- `MapShapeSimplification.Budget.remaining` is invocation-owned, private scratch
  storage passed `inout` through bounded geometry work. Its local mutation is an
  intentional exception to the checker's lexical stored-property rule; public
  domain inputs remain immutable. Preserve its work and cancellation bounds.

New findings and stale baseline entries fail the check. Baseline expansion,
exclusions and tool upgrades require review; do not regenerate the baseline to
silence failures. Inspect rule categories for checker limitations before changing
application behavior. The shared tool owns rule implementations.

EngineeringRules is private. This local gate does not add credentials or a private
fetch to Chio's public CI or package build. Hosted lint requires a separate tool
distribution/access decision; the public platform gate below remains required.

## Running checks

After the shared local check, with Swift 6.4 and Python 3 installed, run from the
repository root:

```sh
bash Scripts/ci/verify.sh
```

The gate serializes builds and hosted tests. It runs all tests in release,
selected tests in debug, a standalone release build, 20 plain-text snapshots and
15 dashboard pseudo-terminal workflows, plus the map example's fixture
reproduction and PTY workflow. Snapshot files are inspection artifacts;
Swift tests assert the rendering contracts.

A focused debug preflight first checks real map HTTP transport and the online
view lifecycle. SwiftPM continues other test targets after one executable fails;
this exposes acquisition regressions before the longer composition suites. The
normal debug/release suites still include these checks.

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

The map example additionally runs `Scripts/maps/prepare-fixtures.py --verify`
and `Scripts/maps/terminal-probe.py` against its release binary. The PTY checks
compare map samples after pan and detail changes, including batched detail keys,
endpoint limits and cycle wrapping, as well as retained camera text, offline
coverage status and terminal restoration. Its `--benchmark` mode measures the first completed hosted UI frame, including
native startup, asynchronous preparation and frame delivery. It uses one warm-up
and three measured fresh sessions per scene/allocation; small allocations measure
the compact summary. Fixture I/O is excluded. These measurements replace the
spike's separate preparation/drawing/raster timings and do not measure SSH latency.
Use `--detail` and `--source` to choose retained input and presentation.
`Scripts/maps/render-snapshot.py` converts `--snapshot-json` exports into
inspection previews with Pillow and explicit text/braille fonts. Its default
fonts are macOS paths; supply `--font` and `--symbol-font` elsewhere. It is an
optional capture tool, not a Swift package or CI dependency.

Shape changes additionally compare land and water fills without labels, preserve
holes and seam behavior, and exercise unsafe-candidate/work-budget fallback.
Compare both world and street captures across detail levels; fewer annotations
alone do not establish geographic shape simplification. Keep abstract/source
captures unchanged when their geometry contracts are unchanged.

Drawing-work changes require exact/over-budget accounting cases and adversarial
overlapping polygons, long strokes and complex rings. Check whole-drawing rejection
before native painting, finite coordinate handling and the fill-disabled path.
The hosted overload workflow verifies retained camera/focus, batched detail keys,
theme changes, fill recovery and resizing; fixed fixtures must still render at
the documented allocations. Work counters are operation allowances, not latency
guarantees; benchmark drawing setup (admission and label placement) separately
from native raster work.

Source-adapter changes additionally check the pinned raw MVT/TileJSON hashes,
malformed/truncated protobuf, tag indices, command state, buffered coordinates,
ring orientation/holes, multipart identities and input/work bounds. Exercise the
real tile through all four shared detail levels, the three themes and narrow
allocations. Hosted checks preserve camera, detail, theme and native focus across application
source replacements. PTY checks exercise marker selection/activation, rapid input,
coverage recovery, resizing and restoration. Provider comparisons are shelved.
`--benchmark --source openfreemap` measures the tile through the same public hosted component; fixed tile resolution does not establish source-level selection,
network acquisition, tile stitching or arbitrary-provider support.

Online acquisition additionally requires complete XYZ coverage/model tests,
viewport admission with whole crossing/enclosing parts and holes, invalid offscreen
selected-data rejection, and retained-region coverage across same-tile pans,
controlled transport/clock checks for cache freshness, two-request admission,
replacement cancellation, budget-only fallback and current-result publication.
A bounded localhost HTTP fixture exercises URLSession response status, MIME,
redirects, decompressed-byte limits and cancellation on macOS/Linux. Python 3 is
required for that fixture. Hosted tests verify loading/failure/retry, retained
source/focus (including an initially absent source), compact recovery and independent
detail/theme changes. Real zoom-1 fixtures verify all four world tiles, complete
coverage across seam pans, coarse edge conversion and land/ocean raster samples
across detail levels, themes and narrow allocations. CI uses no
live provider. Separately inspect bounded OpenFreeMap acquisition and adjacent
tile rendering; this is integration evidence, not an availability guarantee.

Both HTTP fixtures bind numeric loopback directly, preserving the OS-selected
ephemeral port without Python HTTPServer's reverse-DNS lookup. Fixture readiness
must not depend on the runner's DNS configuration. Startup failure diagnostics
retain bounded child output and identify progress through imports and binding.
Test owners await child shutdown even after cancellation or a thrown operation.
Cleanup retains a five-second bound and reports signal results and observed process
state when it fails.

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

The [showcase](https://echoz.github.io/Chio/) serves thirteen recordings and 39
three-theme previews from `Docs/Media`, using the pinned local asciinema player
in `Docs/Site`. Its upstream license remains with the vendored assets. Components
and compositions stay separate; the map component uses the same public API as its local example. Each card identifies Chio APIs, native controls,
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

## Linux and CI

[CI](../.github/workflows/ci.yml) runs on `main` pushes and pull requests using
Xcode 27 and the Swift 6.4.0 Ubuntu 24.04 container. The Linux image uses
[Docker's official ECR mirror](https://www.docker.com/blog/news-from-aws-reinvent-docker-official-images-on-amazon-ecr-public/),
pinned to the same image digest verified from Docker Hub, to avoid depending on
Docker Hub authentication during runner initialization. Builds/tests serialize
within each job; artifacts retain logs, text captures and xUnit reports.

[0.1.0 verification](Releases/0.1.0.md#platform-verification) records the tested
platforms. Ordinary Linux executables need the Swift/Foundation runtime libraries.
Future failures require evidence and must not be hidden by weakened tests.

For static distribution, see the current [dependency decision](Decisions/Dependencies.md#static-linux-blocker).
