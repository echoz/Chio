# 2D geographic maps

**Status:** Accepted public offline component, 2026-10-09. Implementation is in
`Sources/Chio`; `chio-maps` in `Examples/Maps` consumes the public API.
[Plan](../Plan.md) tracks integrated verification and delivery status.

## Public component and ownership

`MapView(source:camera:selection:overlays:detail:)` is a north-up, flat Web Mercator
map. The application supplies a `MapSource`, authoritative camera/selection
bindings and optional `MapOverlays`; minimal detail is the default. `mapFills`,
`mapLabels` and `onActivate` configure presentation and explicit marker activation.
No provider, network request, timer or route calculation is hidden in the view.

SwiftTUI owns allocation, cell metrics, focus, gestures, input, lifecycle and native
Canvas/Text rendering. Chio supplies checked geographic values, projection,
terminal detail, bounded preparation, labels and interaction conventions. One
canvas composes geography and route dots; native Text supplies markers and labels.
The existing `Chio` product exports the component and adapters without a package
split or general map DSL. [Usage](../Usage.md#maps) has the consumer recipe.

### Immutable values and adapters

- `MapCoordinate` holds finite degrees in latitude −90…90 and longitude −180…180.
  `MapCamera` restricts its centre to Mercator's ±85.0511287798066° and its sole
  scale value, longitude span, to 0.0001…360°. Checked pan/zoom return replacements.
- `MapPolyline`, `MapRing`, `MapPolygon`, `MapGeometry` and `MapFeature` describe
  canonical geometry. Rings require closure, three distinct vertices and nonzero
  area; they do not claim complete topology validity. IDs are nonempty and unique
  within `MapDataset`. The supported classes are land, water, park, building,
  road and primary road.
- `MapSource` composes the dataset with required `MapSourceMetadata` and
  `MapCoverage`. Credits, license, source URL and revision remain attached to the
  source. Metadata URLs are HTTP(S) references; reading them does not perform I/O.
- `MapSourceAdapter` is synchronous normalization into `MapSource`.
  `NormalizedGeoJSONMapAdapter` accepts the bounded Chio FeatureCollection subset,
  not arbitrary provider GeoJSON. `MapDataset` retains that GeoJSON coding schema.
  `OpenMapTilesAdapter` accepts uncompressed MVT v2 data, a checked XYZ
  `MapTileCoordinate` and source metadata. Its wire/schema failures are public
  `OpenMapTilesAdapter.ValidationError` values. Canonical geometry failures use
  the checked value's error. Internal parser and projection types remain hidden.
- `MapMarker` has an application-owned ID, coordinate and optional-in-meaning
  title (`""` means unnamed). `MapRoute` has a separate ID namespace, title and
  checked `MapPolyline`; paths are authored by the application. `MapOverlays`
  enforces unique marker/route IDs and aggregate bounds. No provider feature ID
  becomes an application selection ID implicitly.

Owned values have immutable stored properties, synthesized equality/hashing and
sendability where applicable, and checked decoding. Construction, replacement and
coding preserve the same restrictions. Source loading remains at an application
effect boundary; the example reads its bundled fixtures once.

### Bindings, focus and annotations

The map is one native focus stop. Arrows pan by 12% of longitude span in projected
coordinates; plus/minus zoom about the centre. Each key reads the current binding,
so batched input accumulates without waiting for an intervening frame. Rejected
application writes remain rejected. External camera replacements take effect;
external selection changes never implicitly move the camera or invoke activation.

`n`/`p` traverse all supplied markers in input order, including offscreen markers.
From no/unknown selection, next selects the first and previous selects the last.
An accepted selection centres the camera on that marker while retaining zoom;
latitudes beyond the Mercator range centre at the projection limit. A rejected
selection does not pan. Return activates only a currently supplied selected
marker. Tab and Shift-Tab remain native focus navigation. Clicking a visible
marker is supplementary to the full keyboard path. Unknown external selection
IDs are retained, not repaired or cleared when sources/overlays change.

Selected markers use a diamond and accent color, giving a non-color selection cue.
The selected symbol/name reserves space before other markers and labels; overlapping
unselected markers may be omitted from the drawing but remain keyboard-selectable.
Names use native Unicode cell measurement and clip to available space. Optional
route names precede geographic labels. `mapLabels(false)` disables geographic,
route and unselected-marker names while leaving selected-marker names enabled.
Routes survive every detail level, clip at the viewport/dateline and paint above
geography in the same canvas. They are synthetic guides in the example, not
navigation instructions or calculated routes.

### Allocation, themes and fallback

The component uses its actual assigned size through public `GeometryReader`, not
the enclosing terminal's dimensions. Reported physical cell aspect is used when
valid, otherwise the estimated aspect is 2. Drawing is capped at 240×100 cells;
very wide cameras (span ≥180°) letterbox to a square physical world area.

The current minimum drawing allocation is 32×16 cells for camera spans ≥60°,
and 58×16 otherwise, plus two source-credit rows. Below it, a selected-place
summary and resize hint replace geometry while preserving camera, selection and
the native focus target. Pan/zoom/selection remain available. Allocation and aspect
changes create a new preparation request. Expansion restores the current bindings.
Over-budget drawings similarly show recovery guidance without disabling controls.

`ChioTheme.map.water` and `.park` are semantic area-fill colors, independent of
syntax highlighting. Land/buildings use existing surfaces; roads use text colors;
routes and selected markers use accent. Default, light and btop palettes provide
map colors. Theme changes repaint the prepared geometry without resetting state
or requiring another geometry job. Required attribution and license remain visible
within the available width; full source metadata is available to the application.

### Preparation and cancellation

One mounted map lazily creates a serial `MapPreparationWorker` actor. Its immutable
request includes dataset, camera, allocation/aspect, detail, routes and fill mode.
Public `.task(id:)` owns cancellation as inputs change or the view disappears.
CPU preparation and drawing admission run on the actor, off the UI actor.
Cancelled queued requests exit before work; active preparation checks cancellation
between features and within long geometry/generalization loops. Bounds remain
in force independently of cancellation. Native task queuing is not a claimed
constant-memory scheduler under arbitrary unbounded input streams.

Completions retain their full request. The view paints only a completion matching
its current request, and publication checks cancellation and the current camera
binding. Old source, scale, allocation or detail results cannot be painted as the
new request. While preparing, the same focus target and controls remain mounted.
Source/route preparation failures reject the entire drawing; no partial dataset is
silently displayed to stay inside limits.

## Detail and geographic limits

Presentation detail is Chio's policy after normalization. Source resolution is
what the provider supplied; these are independent. Adapters do not redefine
minimal or promise detail omitted by the source. The shared levels are:

| Level | Presentation |
| --- | --- |
| `silhouette` | Broad land/water shapes; omit land/water below 2/4 visible cells²; at most two geographic labels |
| `minimal` | Default: land/water and primary roads; at most four geographic labels |
| `abstract` | Primary roads, quiet parks and scale-dependent minor roads; at most eight labels |
| `source` | All supported source classes, original polygon rings and denser geographic labels |

Silhouette/minimal simplify polygon boundaries by 1.5/0.75 terminal-column widths,
using physical cell aspect. Rings retain their first point and extrema. Candidates
must preserve closure, winding, nonzero area, 85–115% of each ring's area and the
checked intersection/hole relationships. Unproved or over-budget simplification
retains original geometry. Genuine dateline/polar cuts remain exact. Abstract and
source retain original polygon geometry; line sampling still reduces redundant
subcell points. Abstract minor roads require ≤12 ground metres per column and at
least 58×16 drawing cells. Labels use collision spacing and allocation-scaled counts.

This is conservative per-polygon generalization, not a GIS topology proof. Shared
boundaries between separate polygons are not coordinated; area checks do not bound
every narrow channel or exterior-minus-holes area. Source order and visibility can
change which shapes exhaust the simplification allowance. These limitations remain
part of the component's supported scope.

### Work bounds

Canonical input allows 4,000 features and 200,000 vertices, with at most 20,000
vertices per path/ring and 256 rings per polygon. Normalized GeoJSON is limited to
16 MiB. Overlays allow 256 markers, 64 routes and 200,000 route vertices; collection
and path decoders enforce their bounds during traversal. Preparation allows
600,000 vertices and three million shape operations, at most one million per
polygon. Shape budget exhaustion retains original geometry; preparation admission
failure rejects the drawing.

Drawing admission counts geography and routes together: at most two million edge
visits, 16 million crossing-sort weight, 250,000 fill writes and 250,000 stroke
samples. No partial drawing is painted after rejection. These are work allowances,
not universal latency guarantees. Source construction/decoding must also respect
upstream transport limits chosen by the application.

The MVT reader allows 16 MiB input, 64 layers, 20,000 raw features, 65,536 total
key/value entries, one million geometry words and 2 MiB text (16 KiB per string).
Layer extents are 1…65,536 and XYZ zoom is 0…22. Buffered positions are retained
within the documented ±8-extent allowance. Half-world or longer tile-space edges
reject before longitude wrapping. Multipart parts receive snapshot-local IDs;
those IDs are not stable across provider revisions or neighboring tiles.

## Coverage and deferred provider work

The adapter proof is accepted. On 2026-10-09 the user explicitly shelved provider
comparisons to prioritize the reusable component. Matching fixture footprints,
provider parity, distinct no-data painting and artificial tile-edge treatment are
not completion gates for this slice. Keep these limitations explicit:

- `worldwide` or a checked nonwrapping offline query box describes availability.
  The current notice checks the camera centre, not complete viewport coverage.
  Uncovered space still uses the base surface. Panning never loads more vectors.
- The retained OpenFreeMap example is one z14 tile, with buffered/clipped rings.
  Cut edges can still be outlined as geographic boundaries. There is no stitching.
- OpenMapTiles water/building/park and selected green-space landuse polygons,
  plus selected transportation classes, normalize into the shared model.
  Standalone point/label layers, generic landcover, waterways and service/path
  roads are outside this adapter's subset. A provider may therefore show different
  names/classes even when the underlying OSM geometry agrees.
- The retained eastern tile has 384 canonical features. Its denser western neighbor
  expands to 4,797 and exceeds the feature allowance; it is not silently truncated.

<a id="later-proposal-vector-tile-loading"></a>
### Later acquisition work

Live tile loading, neighboring coverage, caches, cancellation of network work,
credentials, PMTiles/MBTiles, geocoding and routing services remain deferred.
Any later loader needs explicit missing/loading/failed tile behavior, bounded
concurrency/cache sizes, attribution and stale-result handling. The current adapter
normalizes supplied bytes and performs no I/O. No additional package dependency
was introduced; existing static Linux limitations remain in
[Dependencies](Dependencies.md#static-linux-blocker).

<a id="rendering-spike-findings"></a>
## Proof record and verification

The [pre-promotion decision](https://github.com/echoz/Chio/blob/dade20683f682a78da8b4c3507901cbf3f510200/Docs/Decisions/GeographicMaps.md)
retains the rendering spike's measurements, constraints and implementation history.
Both adapters feed the same geographic model and renderer; a bounded raw-data
comparison found sampled Marina Reservoir boundaries agreeing within 0.4 m in
shared coverage. That establishes the checked sample's coordinate conversion,
not general provider parity or global topology correctness.

[Fixture provenance](../../Examples/Maps/Fixtures/Provenance.md) retains pinned
Natural Earth, Overpass and OpenFreeMap sources, hashes and licenses. Natural
Earth is public domain; OSM-derived inputs retain ODbL and provider attribution.
OpenFreeMap supplies the OpenMapTiles schema; neither schema nor source format
becomes the public view API. The example uses only bundled local data.

Verification follows [Verification](../Verification.md): checked construction and
incremental decoding, projection/holes/dateline/work limits, marker/route raster
priority, cancellation and stale requests, application-authoritative bindings,
native focus, actual allocation and resize recovery, release PTY behavior, and
separate macOS/Linux evidence. Recordings/previews consume the public component;
local raster/PTY/browser checks do not establish live Ghostty/Blink SSH latency.
The promoted `--benchmark` measures first completed hosted-frame time, including
native startup and preparation, rather than the old separate geometry/raster probe.

<a id="geographic-maps-proposed"></a><a id="proposed-next-slice-2d-maps"></a>
<a id="1-prove-the-terminal-rendering"></a><a id="2-build-the-reusable-offline-component"></a>
<a id="3-verify-and-publish-the-first-slice"></a><a id="evidence-and-dependency-decisions"></a>
Earlier proposal anchors remain for links; current contracts are documented above.
