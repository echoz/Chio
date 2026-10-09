# Chio verification

Current requirements for implementation, dependency and visible example changes.
[Plan](Plan.md) tracks active work; [release records](Releases/0.1.0.md) preserve
revision-specific results. For documentation-only changes, check links, anchors
and preservation of current contracts.

## Running checks

With Swift 6.4 and Python 3 installed, run from the repository root:

```sh
bash Scripts/ci/verify.sh
```

The gate serializes builds and hosted tests. It runs all tests in release,
selected tests in debug, a standalone release build, 20 plain-text snapshots and
15 dashboard pseudo-terminal workflows, plus the map example's fixture
reproduction and PTY workflow. Snapshot files are inspection artifacts;
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
Xcode 27 and the Swift 6.4.0 Ubuntu 24.04 container. Builds/tests serialize within
each job; artifacts retain logs, text captures and xUnit reports.

[0.1.0 verification](Releases/0.1.0.md#platform-verification) records the tested
platforms. Ordinary Linux executables need the Swift/Foundation runtime libraries.
Future failures require evidence and must not be hidden by weakened tests.

For static distribution, see the current [dependency decision](Decisions/Dependencies.md#static-linux-blocker).
