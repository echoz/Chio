# Online tile acquisition

**Status:** Accepted decision and implementation, 2026-10-09.
[Plan](../Plan.md) lists delivery gates.
[Geographic maps](GeographicMaps.md) continues to own projection, geometry bounds,
interaction and rendering.

## Explicit effects and source configuration

`MapView` never discovers or downloads data. `onViewportChange` reports its actual
drawable `MapViewport`, or nil for the compact fallback. The application pairs
that allocation with its authoritative camera in `MapTileRequest` and explicitly
calls `MapTileLoader.load`. A successful `MapTileSnapshot` correlates the source,
request and requested/attained source zoom. Its checked `.tiled` coverage must
cover every required viewport tile and the retained geographic region; a
centre-only match is insufficient. `MapTileCoverage` requires both its acquired
tiles and the `MapTileRequest` whose geometry was retained.

`OpenMapTilesSource` holds a checked HTTP(S) XYZ path template, zoom range and
required attribution. It is a pure immutable value. Compatible endpoints can be
substituted without changing the renderer or loader; this does not establish
compatibility with arbitrary MVT layer schemas. `fetchOpenFreeMap()` is a named,
explicit discovery operation, using `https://tiles.openfreemap.org/planet`.
Discovery accepts only HTTPS tile templates on the provider's tile host.
The example can also decode a checked `OpenMapTilesSource` from an explicit
`--tile-source` JSON file (at most 16 KiB), requiring `--online`.

The default example remains offline. `--online` selects online tiles at every
camera scale, including the world overview; it never switches to Natural Earth.
Before the first successful load, `MapView(source: nil, ...)` keeps its allocation,
native focus and camera/marker controls active without claiming geographic data
or attribution. Later loads and failures retain the last accepted online source
and label previous coverage. They do not claim that old tiles cover a new area.
Camera, marker selection, theme and visual detail remain application/native state.

World acquisition uses source zoom 1 or above: four zoom-1 tiles cover the entire
world within the existing 16-tile allowance. The provider advertises zoom 0, but
its buffered full-world polygons contain translated copies of islands whose
relative branch cannot be recovered from canonical longitude alone. Supporting
those inputs would require geometric decomposition or a richer representation.
Zoom 1 supplies full online world coverage without either change. Sources whose
maximum is below 1 reject explicitly. This replaces the initial hybrid policy
(bundled world, online regions/streets).

## Resolution, limits and cancellation

The planner enumerates all intersecting XYZ tiles with half-open boundaries,
wrapped X and clamped Mercator Y. It rejects requests exceeding 16 tiles before
enumeration. Desired source zoom targets roughly 48 terminal columns per tile.
Source zoom is independent of `MapDetail`, which still controls presentation
after normalization. The loader validates selected source parts, then conservatively
culls complete parts whose projected bounds cannot intersect the viewport. It
reuses the renderer's sequential longitude unwrapping, whole-hole branch alignment
and world copies. Polygon admission checks every accepted ring; containment in
the exterior is not a construction or decoding guarantee. Crossing
lines, enclosing polygons and all retained holes remain whole; identities retain
their original multipart indices. Malformed selected geometry or names reject
even outside the viewport. No clipping or simplification happens at acquisition. Coarse Cartesian edges
are subdivided before canonical longitude conversion to retain their direction;
this adds collinear points without changing provider shapes. See the geometry
constraints in [geographic maps](GeographicMaps.md#work-bounds).

Absent names normalize to empty strings; a present name must be a string.
Numeric/Boolean selected names reject with `invalidValue`, including offscreen
features. This corrects their previous silent normalization to unnamed features.

The unchanged 4,000-feature/200,000-vertex limits apply to the retained aggregate.
Raw wire, record, path and polygon bounds still apply before culling. The public
whole-tile `OpenMapTilesAdapter.adapt` continues to enforce whole-tile limits. A
loaded source claims only its retained region, not every position inside its acquired tiles;
panning within cached tiles repeats admission for the new viewport.

MVT records may group hundreds of separate buildings or roads. The decoder's
record allowance is 4,000 paths and 200,000 vertices, including polygon closures;
256 rings remains a limit on each actual polygon. Paths and canonical polygons
retain their 20,000-vertex limits, independent of the tile's one-million-word wire
allowance. This corrects the earlier conflation of multipart records with polygon
holes; [geographic limits](GeographicMaps.md#work-bounds) record the acceptance
change and unchanged canonical constraints.

Only resource-budget failures retry at a lower source zoom: requested zoom and
at most its two predecessors, bounded by source minimum and zoom 1. A successful
fallback exposes both zooms. Malformed geometry, HTTP failures and unsupported
schemas fail the request. No required tile or potentially visible part is omitted
to fit a count budget. Dense visible areas may still fail after all three bounded
attempts. Lower zooms are not guaranteed to contain fewer supported features.

Per-path limits include polygon closure vertices. Otherwise valid oversized paths
report `budgetExceeded`, correcting the former `invalidGeometry` classification
that prevented fallback. The decoder streams the rest of the wire-bounded record
without retaining excess geometry so malformed commands, coordinates, duplicates
or polygon ordering still fail as geometry errors before a budget retry. This
does not change error precedence across separate features or tiles.

Each `MapTileLoader` actor belongs to one map consumer. A new load cancels and
drains its predecessor before starting at most two HTTP operations. A generation
check prevents a superseded waiter from starting another operation. Callers still
correlate publication with their current request. The whole load has a 30-second
deadline; individual resources have a 20-second timeout. Cancellation is checked
between decodes; existing wire and geometry bounds limit synchronous work.

The memory cache stores raw responses: at most 64 entries and 32 MiB, with a
30-minute maximum lifetime and LRU eviction. `no-store`, `no-cache`, `max-age`
and `Age` restrict reuse. There is no disk cache, background prefetch or automatic
HTTP retry. A loader's immutable source configuration scopes its cache.

The internal URLSession delegate owns a locked mutable transfer lifecycle, with
exactly-once continuation completion and explicit task/session teardown. It is a
documented resource-owner exception to immutable value properties. Ephemeral
sessions disable shared caches, cookies and credentials. Response status and MIME
are checked; redirects stay on the same origin and are limited to three. The
delegate bounds decompressed bytes incrementally: 256 KiB for the catalogue and
16 MiB per tile. `Content-Length` is only an early check. Rejection explicitly
cancels the task because FoundationNetworking's response-disposition handling
differs from Darwin's. Empty HTTP 200 tiles remain valid empty geometry; HTTP
errors do not become empty tiles.

Redirect decisions are queued before Chio requests cancellation. Reversing that
order triggered a FoundationNetworking waiting-state trap on Linux. The transfer
lock orders Chio-owned decisions and cancellation; an already-cancelled corelibs
redirect callback is left stale because cancellation independently delivers the
terminal acknowledgement. Darwin still receives the nil redirect decision.
This is a narrow compatibility workaround for
[corelibs' redirect state machine](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/FoundationNetworking/URLSession/HTTP/HTTPURLProtocol.swift),
not a general permission to omit active URLSession delegate completions. A native
Foundation deadline can change its internal protocol state independently of this
lock; races with that upstream transition remain a limitation.

## Provider evidence and remaining limits

OpenFreeMap's public service needs no API key and supports interactive map use.
Keep its OpenFreeMap, OpenMapTiles and OpenStreetMap/ODbL attribution. It provides
no SLA. Do not turn this loader into a bulk downloader. See the provider's
[documentation](https://openfreemap.org/), [terms](https://openfreemap.org/tos/),
[privacy policy](https://openfreemap.org/privacy/) and
[version behavior](https://github.com/hyperknot/openfreemap#tile-versions).

Bounded observations on 2026-10-09 found the canonical catalogue advertising zoom
0…14 and a dated template; `/planet/latest` returned an older cached catalogue.
A request above the advertised maximum returned HTTP 200 with zero bytes. The
loader respects the advertised range. Deleted version paths can serve current
tiles, so `sourceRevision` records the observed template, not a claim that served
bytes are immutable or from one atomic provider snapshot.

Adjacent tiles are normalized and aggregated. Buffered geometry can overlap,
and clipped polygon edges can appear as artificial outlines. This is not polygon
stitching or a topology engine. Provider comparison work remains shelved.

Disk caching, downloadable tile packs, geocoding and route calculation were
excluded from this delivered acquisition slice. They are now
[approved follow-up scope](../Plan.md#approved-map-expansion), with implementation
pending. The memory-only cache and explicit online/offline behavior above remain
the shipped contract. Pack acquisition needs a separately evaluated source and
download policy; this approval does not turn the interactive loader into a bulk
downloader. Credential storage remains application-owned.

There is no new Swift package dependency. FoundationNetworking on Linux adds its
normal libcurl transport requirements; existing static Linux limitations in
[Dependencies](Dependencies.md#static-linux-blocker) remain unproved by this work.

## Verification boundary

Checked model/planner tests cover tile edges, wrap, poles, complete coverage,
template restrictions and decoding. Spatial admission tests preserve whole
crossing/enclosing geometry, holes and IDs, reject malformed offscreen selected
parts, and distinguish retained regions from tile footprints. Injected transport/clock tests exercise cache,
replacement, concurrency, fallback and failure without a public service. Local
HTTP integration tests exercise the real URLSession boundary on supported CI
platforms. Hosted and terminal checks cover source replacement and native focus.
Four retained genuine zoom-1 responses exercise world acquisition, coastline/hole
placement, seam pans, all detail levels, themes and narrow raster allocations.
Separate bounded live-provider checks establish integration, not service uptime,
universal data coverage, provider parity or SSH latency.
