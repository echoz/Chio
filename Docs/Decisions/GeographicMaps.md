# 2D geographic maps

**Status:** Rendering spike implemented, 2026-10-08. The reusable Chio component
and its public API remain proposed.

Prove world and street maps from vectors within native SwiftTUI rendering.
The [active plan](../Plan.md) tracks the next steps. Experimental code lives in
`Spikes/MapRendering`, built as `chio-map-spike`; it is not exported by `Chio`.

## Rendering spike findings

### Abstract presentation and source adapters

The user selected minimal as the preferred visual direction on 2026-10-09; it is
now the example default. The earlier abstract treatment remains available for
comparison. In abstract mode, buildings are
omitted, major roads keep their connected source paths, and minor roads appear
only at scales of at most 12 ground metres per column with a 58×16 or larger allocation.
The source converter classifies motorway/trunk/primary roads, including links,
as major; secondary and tertiary streets remain in the ordinary-road category.
Small visible areas are omitted using filled area after viewport intersection,
with holes deducted. Abstract and source keep their original polygon rings.
Parks use quiet fills without outlines. Abstract labels have wider spacing and
a budget of one per 300 cells, capped at eight. These are experimental defaults,
not a promise of a finished map style or general-purpose level-of-detail engine.

The live detail control has four ordered levels, selected with `[` / `]`:

| Level | Presentation |
| --- | --- |
| 1. `silhouette` | Broad land/water shapes; omit areas below 2 and 4 cells² respectively; at most two labels |
| 2. `minimal` | Default: more faithful land/water shapes plus major roads; at most four labels |
| 3. `abstract` | Major roads, quiet parks, scale-dependent minor roads and at most eight labels |
| 4. `source` | All available feature classes and the original denser label policy |

The two lower levels use wider label spacing, with one label per 800/500 cells
respectively and a minimum budget of one. Brackets stop at the endpoints; `d`
cycles and wraps. The header shows the level number and name. `--detail` chooses
the initial level, including in snapshots and benchmarks; `--source-detail`
remains a compatibility alias that takes precedence. The abstract and source
treatments remain available. These are discrete semantic presets for the
spike, not a public API commitment. They do not merge parallel roads, remove
individual junction branches or fetch additional vectors.

The first detail control only selected layers, small areas and labels. The lower
two levels now also generalize the actual land and water polygon boundaries,
including the geometry used for area fills. Silhouette/minimal use tolerances of
1.5/0.75 terminal-column widths, with row distances scaled by cell aspect. Zooming
in naturally retains more geographic detail. Abstract/source keep exact polygon
geometry, so the previously accepted default remains a comparison.

The closed-ring reduction retains the first vertex and all extrema. It accepts a
whole polygon only after checking source and candidate rings for closure, finite
coordinates, winding, nonzero area, self intersections, boundary crossings, and
contained, nonnested holes. Each ring must retain 85–115% of its area. Unsafe or
unproved candidates retain exact input; these guards do not repair malformed
topology. Polar/clamped and genuine dateline-crossing polygons remain exact;
merely seam-touching rings retain their cut vertices as extrema.

Source-based viewport culling and area admission precede this work. A preparation
shares a three-million-operation allowance, with at most one million per polygon
for distance/topology checks. Exhaustion retains the original polygon. Retained
features remain nested across detail levels, but vertex counts need not be:
different tolerances can independently fall back. Fills, outlines and label
anchors use the same accepted rings. Source fixtures remain unchanged.

This is a conservative per-polygon rendering experiment. Separate features do not
coordinate shared boundaries; per-ring area checks do not bound every local
channel width or the exterior-minus-holes area. Fixed-epsilon predicates are
conservative checks, not robust GIS topology proofs. Budget fallback can retain
different features at exact detail depending on source order and visibility.
This does not establish general GIS topology preservation or arbitrary-input
performance. The separate drawing allowance below bounds downstream work.
Visual comparison of real
world/street data remains part of choosing these provisional tolerances.

Themes supply color; the semantic detail policy is
independent of both the theme and the provider. Low-level preparation defaults to
source mode for geometric contract tests; the executable explicitly chooses the
minimal mode. Panning and detail changes retain the camera.

An internal synchronous `MapSourceAdapter` normalizes a typed input into
`MapSource`: the existing checked `MapDataset` composed with required source
metadata and explicit geographic coverage. `NormalizedGeoJSONMapAdapter` accepts
the spike's existing bounded GeoJSON schema; it is not an arbitrary provider's
GeoJSON decoder. Fixture I/O occurs once at the command boundary. The provenance
manifest supplies attribution, license, source URL and revision rather than
duplicating those facts in a scene's presentation.

Coverage distinguishes worldwide data from a checked, nonwrapping offline query
box. Singapore coverage is the query box, not the extent of complete geometries
that happen to cross it. The UI identifies the offline extract and reports when
the camera center leaves it; this is a center-based notice, not proof that every
visible cell is covered. It neither clamps the camera nor requests more data.
The source adapter owns normalization; acquisition, tile caching, cancellation
and asynchronous preparation remain deferred. No public library API or network
dependency is added by this seam.

A local release comparison uses the same retained street dataset and 20 timed
samples after warm-up. At a **100×30 map allocation**, abstract preparation retains
at most 643 visible features and 3,614 prepared vertices, compared with 2,212 and
19,761 in source mode. Preparation/raster medians are about 0.9/5.9 ms versus
3.0/19.8 ms. At 60×20 and 36×18 map allocations the abstract raster medians are
about 3.3 and 2.2 ms. As in the initial probe below, timing uses uniform area colors;
the native UI's three-theme captures are checked separately. These observations
do not establish worst-case budgets or SSH latency.

The earlier abstract 100×30 **terminal UI** has a 98×20 street allocation and six
labels. A 60×26 terminal keeps a readable map with three labels and compact pan,
detail, zoom and scene hints. The updated recording compares all four detail levels
and ends on the final complete UI frame. Terminal verification compares drawing
samples after panning and toggling detail, and checks the outside-coverage notice.

### Drawing work and overload

Drawing now has a checked construction boundary before native Canvas painting.
It admits the complete immutable drawing or throws `drawingBudgetExceeded`;
there is no partial paint, silent geometry removal or automatic detail change.
The view presents “Too much map detail” and keeps its camera, native focus and
controls. Changing scale/detail or disabling fills can admit a new drawing.

The provisional per-drawing allowances are two million scanline edge visits,
16 million crossing-sort work units, 250,000 fill-cell writes and 250,000 stroke
samples. Counts use actual geometry rather than diagnostic statistics. Validation
also bounds collection traversal and rejects nonfinite projected coordinates.
All polygon rings contribute to clamped bounds, including source holes outside
an exterior: drawing admission must not silently repair accepted source topology.
Only rows with possible cell-center coverage are scanned. Each polygon's bounding
cell rectangle bounds its disjoint even-odd fill intervals, including overdraw
from repeated polygons. Finite interpolated crossings are clamped to their segment
bounds so numerical cancellation cannot paint beyond that allowance.
Stroke counting and painting share the same clipped
2×4 sampling calculation, including both endpoints of each segment.

The crossing-sort weight is a conservative complexity estimate, not a count of
Swift's actual sort comparisons. These allowances bound the named drawing work,
not wall-clock latency, native renderer internals or arbitrary-input preparation.
The existing checked input/prepared-vertex limits and separate shape-simplification
budget still apply. Preparation remains synchronous; cancellation and rejection
of stale work are required before promoting a reusable component. Label/source
validation remains at its existing boundary rather than being established by
the drawing check.

The release regression matrix admits both fixtures at all four detail levels,
at 100×30, 60×20 and 240×100 map allocations, with initial and panned/zoomed
cameras. Adversarial tests independently reach the fill, edge and stroke limits,
reject excessive sort work, and reject 4,000 overlapping full-screen polygons.
A native hosted test retains focus and camera through overload, pan, theme,
fill/detail recovery and resize. A raster regression covers interpolation rounding
at extreme finite coordinates.

Local release measurements at a 100×30 map allocation use 20 samples after
warm-up. Minimal world preparation/setup/raster medians are approximately
2.30/0.01/1.91 ms; street is 1.15/0.03/3.87 ms. Setup includes drawing admission
and label placement. Peak fill-write allowances are 2,598/2,516 and stroke samples
2,728/4,968 for world/street respectively. Full-source street setup is about
0.24 ms with a 19.8 ms raster median. These are fixture measurements, with the
probe's uniform area colors, and make no SSH or worst-case latency claim.

### Initial rendering proof

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
- Singapore: 2,822 features, 20,494 source vertices and 17 holes. Road reclassification
  changes the normalized GeoJSON bytes without changing geometry; the manifest
  records current byte counts and hashes.
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

The initial street overview was too dense. Offline source filtering, line sample reduction
and label collisions are useful, but do not establish sufficient cartographic
detail reduction: short road fragments and small building outlines still compete
for cells. Before promotion, compare zoom/allocation-based layer admission and
coalescing of road geometry. Preserve meaningful roads and polygon holes; dropping
arbitrary samples to obtain a faster frame is not an acceptable policy.

### Measured scope and remaining limits

The initial `ea624b7` macOS arm64 release measurements use the two bundled datasets and 20 samples
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

At the initial proof, input limits alone allowed 4,000 overlapping full-screen
polygons to cause 96 million cell writes at 240×100. The drawing allowance above
now rejects this before painting. Separate preparation/cancellation policy and
measured rapid-input behavior remain required before public application-supplied
datasets; a finite operation allowance is not a frame-time guarantee.

Decoding happens once at the CLI boundary. Preparation currently runs synchronously
when the experimental view changes. This intentionally measures the basic path;
it does **not** satisfy the proposed asynchronous cancellation/stale-result contract.
Markers, routes, feature selection, authoritative external bindings, pointer hit
testing, live tiles, limited-color readability and live Ghostty/Blink SSH behavior
remain unproved or unimplemented. Do not promote these internal types unchanged.

### Verification of the proof

The initial proof's 27 map tests passed in debug and release: checked construction/decoding, projection
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
