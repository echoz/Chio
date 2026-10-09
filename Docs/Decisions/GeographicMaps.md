# 2D geographic maps

**Status:** Rendering spike implemented, 2026-10-08. The reusable Chio component
and its public API remain proposed.

Prove world and street maps from vectors within native SwiftTUI rendering.
The [active plan](../Plan.md) tracks the next steps. Experimental code lives in
`Spikes/MapRendering`, built as `chio-map-spike`; it is not exported by `Chio`.

## Rendering spike findings

One native `Canvas` renders real Natural Earth world land and an OpenStreetMap
neighborhood around Singapore's Marina Bay. It combines braille coastlines/roads
with cell-background area fills; native `Text` supplies labels. Native input,
focus, resizing and lifecycle own interaction. No new dependency, renderer,
layout engine or network service was added.

The experiment deliberately compares area fills and labels with `f` and `l`.
World/Singapore switch with Space; pan, center-based zoom, reset and all three
Chio themes work in the same view. `--cell-aspect` lets measurements compare cell
height/width ratios; normal use reads native reported metrics or the estimated
2:1 fallback. It does not improve native terminal capability detection.

### Data and preparation

- World: 127 polygons, 5,143 source vertices and one hole, 133,553-byte GeoJSON.
- Singapore: 2,822 features, 20,494 source vertices and 17 holes, 909,635-byte GeoJSON.
- [Provenance and reproduction](../../Spikes/MapRendering/Fixtures/Provenance.md)
  retain exact source snapshots, dates, licenses, source pins and a deterministic
  converter. Natural Earth is public domain; OSM data remains ODbL with visible
  attribution. The repository's MIT code license does not relicense that data.
- Checked immutable values reject invalid coordinates, cameras, rings and budgets,
  including decoding paths. Runtime accepts the fixtures' narrow GeoJSON subset;
  this is not a general GeoJSON/GIS implementation or topology validator.
- Preparation projects Web Mercator with the explicit ±85.05112878° cutoff,
  unwraps ordinary dateline crossings, preserves full-world polar cuts, culls
  polygons, clips lines and reduces samples within 0.25 cell. Rings/holes retain
  source geometry; scanline fills intersect only allocated rows.
- A single Canvas preserves all layers' braille masks. One foreground per cell
  means the highest-priority road determines the color of every lit dot in a
  crossing cell. Cell backgrounds preserve fills beneath strokes; holes expose
  underlying layers. Labels use native Unicode widths, stable priority, edge and
  collision rejection, and a finite count tied to allocation.

### What the pictures establish

World coastlines and the neighborhood's river, reservoir, parks and roads are
recognizable at a 100×30 terminal. Default, light and btop preserve hierarchy.
The full-world Web Mercator view is physically square and letterboxed; high
latitudes dominate it. That is a projection tradeoff, not stretch caused by
terminal cell shape. An alternative world overview projection remains worth
comparing before making a public camera/projection promise.

100×30 includes a 20-row drawing; CLI header/credits/controls consume ten rows.
Forced drawings at 60×20 and 36×18 retain geography but lose useful street detail.
The provisional floor is a 32×16 world allocation or 58×16 street allocation;
60×26 terminals satisfy both with 2:1 cells. Other cell ratios can require more
space. Below it, the normal UI shows a summary and retains its camera for resize.
`--inspect-small` bypasses that policy for comparisons, without implying usability.

The street overview is still dense. Offline source filtering, line sample reduction
and label collisions are useful, but do not establish sufficient cartographic
detail reduction: short road fragments and small building outlines still compete
for cells. Before promotion, compare zoom/allocation-based layer admission and
coalescing of road geometry. Preserve meaningful roads and polygon holes; dropping
arbitrary samples to obtain a faster frame is not an acceptable policy.

### Measured scope and remaining limits

Local macOS arm64 release measurements use the two bundled datasets and 20 samples
after one warm-up, with a fresh native renderer per frame. These are **map allocations**,
not full terminal sizes. Preparation and raster medians in milliseconds:

| Map allocation | World prepare / raster | Street prepare / raster |
| --- | --- | --- |
| 100×30 | 0.4 / 3.0 | 3.3 / 21.7 |
| 60×20 | 0.4 / 2.0 | 3.4 / 11.5 |
| 36×18 | 0.4 / 1.6 | 3.5 / 7.6 |

These are an exploratory baseline, not a frame-time guarantee. Maximum observed
prepared geometry reached roughly 9,600 world vertices and 20,700 street vertices
(including retained fill rings and stroke paths). The timing probe uses uniform
selected-surface area colors; separate visual checks assess the UI's water/park
tints in each theme. Maximum observed
street preparation/raster times were about 3.8/23 ms; a separate child-process
resource observation peaked near 47.3 MiB RSS. The unstripped release executable
was about 47.9 MiB; it also needs its SwiftPM fixture resource bundle. No static
Linux distribution claim follows from this experiment.

The local PTY sequence produced about 223 kB for world/street switching, zoom,
pan, a theme change, fill/label comparisons, resize and reset. Individual street
transitions emitted roughly 24–33 kB. The probe records settlement time, including
deliberate quiet waits; it is not an input-to-pixel latency benchmark. Bandwidth
is another reason to reduce overview detail before assuming pleasant SSH use.

Input limits make work finite, not predictably fast: 4,000 overlapping full-screen
polygons could still cause 96 million cell writes at 240×100. Only bounded fixtures
were performance-tested. A drawing/preparation work budget and overload policy
are required before accepting arbitrary application-supplied datasets.

Decoding happens once at the CLI boundary. Preparation currently runs synchronously
when the experimental view changes. This intentionally measures the basic path;
it does **not** satisfy the proposed asynchronous cancellation/stale-result contract.
Markers, routes, feature selection, authoritative external bindings, pointer hit
testing, live tiles, limited-color readability and live Ghostty/Blink SSH behavior
remain unproved or unimplemented. Do not promote these internal types unchanged.

### Verification of the proof

27 map tests pass in debug and release: checked construction/decoding, projection
and aspect, clipping, dateline/polar rings, holes, label anchors/collisions/Unicode,
layer color priority, real fixtures and minimum allocation. Independent review
found a collapsing polar strip and an edge-anchored road label; both are fixed
with regressions. The full macOS gate passes, including all existing snapshots
and terminal workflows, offline fixture reproduction and the added map PTY check.

The showcase has an explicit Experiments category, a 13-second terminal recording
and three native-raster theme previews. Local Chromium checks cover playback,
pause, seeking, theme-linked commands, retained navigation, a 390-pixel layout,
script-free previews and missing-asset fallbacks. These checks do not establish
appearance in every terminal emulator or browser.

## Geographic maps (proposed)

The requested direction is a flat **2D geographic map**, supporting world and
street views from vectors, with detail adapted to the available terminal space.
No map component ships in 0.1.0. The delivery gates below define the proposed
implementation sequence; names and public APIs remain open.

Start with one north-up, pannable, zoomable view and local world/neighborhood
fixtures. Propose Web Mercator to share a camera with common street tiles; make
its latitude limit explicit rather than claiming coverage of the poles. Rotation,
tilt, terrain, routing services and a general GIS engine are outside this slice.

Chio's reusable value is geographic projection, terminal-aware detail, readable
labels, location/route overlays and native map interaction. SwiftTUI still owns
layout, focus, gestures, cells and terminal rendering. Prepare geometry for its
public Canvas/Shape APIs and compose labels with native Text. Reuse the theme
environment; distinguish roads, water, land and selected overlays without making
color the only selection cue. Do not introduce a second terminal renderer.

Keep checked geographic values, camera configuration and prepared geometry
immutable. Distinguish geographic coordinates from projected/tile coordinates;
derive scale from one camera representation and the current allocation. Camera
bindings remain application-authoritative. No selection is meaningful absence;
an empty successful feature set is distinct from loading or failure. Source
schema types stay behind decoding, with provenance and attribution retained.

Choose detail from zoom, allocation and native cell pixel metrics, including
their estimated fallback. Request suitable source detail, cull and clip before
drawing, simplify at the visible sample scale, then place labels by priority and
collision checks. Preserve polygon holes, tile seams and selected locations or
routes. Bound input, preparation and drawing work; renderer clipping alone does
not bound the cost of offscreen segments. Minimum usable allocations must be
measured for world and street views. Below them, show a compact location/selection
summary and a resize hint, preserving camera and selection for expansion.

The pinned native Canvas packs multiple braille samples into a cell with one
foreground/background pair. Overlaid canvases do not merge their dot masks.
Prove geographic layers in one drawing with explicit per-cell paint priority;
assess native Shapes for fills without assuming independent subcell colors.
Use reported cell aspect where available so geography is not stretched. Pan,
center-based zoom and selection use native focus/input/gestures; pointer input
is supplementary to keyboard interaction and may have only cell precision.

Expensive decoding and preparation belong outside the draw closure. An explicit
effect owner bounds and cancels work, correlates results with the current camera,
source and allocation, and rejects obsolete results. The first example reads
bundled fixtures. Any later tile adapter must define cache, cancellation, error
and attribution behavior without adding hidden I/O to values or views; provider
credentials and network policy remain application-owned. No loader product or
dependency is selected by this proposal.

## Proposed next slice: 2D maps

Delivery gates proposed on 2026-10-08. The user wants world and street maps,
vector input, detail reduction and a minimum usable size in a flat 2D presentation.
The findings above record what the rendering experiment establishes and leaves
open. The gates below remain requirements for the reusable component; the spike
alone does not deliver that API.

Build one composable map with themed geography, readable labels, locations and
route overlays. Keep source loading separate from presentation. The proposed
design boundary above retains SwiftTUI's renderer, layout, input and focus.
The first usable deliverable is an **offline world and
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

Run the existing [verification gate](../Verification.md#running-checks), adding a bounded release
terminal workflow and the map regression suites without weakening existing checks.
Measure rapid pan/zoom against the budgets from the proof. Exercise macOS and
Linux separately; keep live Ghostty/Blink SSH appearance and latency evidence
distinct from local raster and PTY results. Verify estimated cell metrics and
limited-color readability without reopening the shelved color-detection work.

Update public usage, example commands and README inspiration credits. Add the
map component to the [showcase](../Verification.md#demo-site), including matching recordings,
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
