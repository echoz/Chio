# 2D geographic maps

**Status:** Proposed, 2026-10-08; no implementation or shipped API.

Prove world and street maps from vectors within native SwiftTUI rendering.
The [active plan](../Plan.md) tracks the next steps.

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

Planning proposal, 2026-10-08. The user wants world and street maps, vector input,
detail reduction and a minimum usable size in a flat 2D presentation. Research
supports a prototype; rendering quality, performance and dependency suitability
are not yet proved. This proposal adds no shipped API or implementation.

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
