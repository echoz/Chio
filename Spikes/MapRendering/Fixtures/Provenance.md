# Offline vector fixtures

These are real source geometries, retained for the experimental rendering spike.
Runtime uses only `world.geojson` and `singapore.geojson`; it performs no fetch.
Machine-readable source pins, snapshot times, SHA-256 hashes, bounds and feature/
vertex/hole counts are in [provenance.json](provenance.json).

World: Natural Earth 1:110m land from its [maintainer's repository](https://github.com/nvkelso/natural-earth-vector), pinned to commit
`693f11422f4e08d2da4566b854dda53eb7c39fb3`.
Natural Earth's [terms](https://www.naturalearthdata.com/about/terms-of-use/) place
these vectors in the public domain. Courtesy credit: “Made with Natural Earth.”
The South Pole boundary of Antarctica includes the original full-width segment
`[-180,-90]` to `[180,-90]`; it must not collapse under shortest-dateline unwrapping.
Projection latitude clipping belongs to rendering; this fixture retains the poles.

Singapore: OpenStreetMap data retrieved from the [Overpass API](https://overpass-api.de/api/interpreter),
database timestamp `2026-10-09T03:27:04Z`. The query selects intersecting ways and
relations in longitude `103.842…103.870`, latitude `1.278…1.300`; complete ways and
relation members extend beyond that box. The fixture includes Marina Reservoir,
Singapore River, Dragonfly Lake, Gardens by the Bay, Esplanade Park, named building
footprints and real road centerlines. Suggested initial camera: longitude
`103.856`, latitude `1.289`, longitude span approximately `0.030`.

The Singapore fixture and retained raw snapshot are distributed under
[Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
Display **© OpenStreetMap contributors** with
[openstreetmap.org/copyright](https://www.openstreetmap.org/copyright) in the map UI
and derived captures; make its ODbL availability clear. The GeoJSON retains
attribution and license foreign members for inspection. Chio's code license does
not relicense OSM data. The complete transformed database, source snapshot and
conversion script are supplied here for ODbL access and exact reproduction.

## Transformations

The standard-library Python converter emits GeoJSON FeatureCollections with stable
string feature IDs, `kind` and string `name` properties, and WGS84 `[lon,lat]`
coordinates. Missing names become empty strings. No coordinates are simplified,
rounded, fabricated or projected. Polygon winding is normalized to GeoJSON's
right-hand rule; holes are preserved.

Natural Earth source feature order and multipart index identify world polygons.
OSM ways use their source IDs. Multipolygon relation member ways are joined at
exact shared endpoints; unclosed chains fail. Outer rings become separate Polygon
features with stable part indices. Each hole attaches to its smallest containing
outer ring. Area members represented by a relation are omitted as duplicates.
Building relations with explicit `outline` members contribute those footprints;
parts-only building relations are omitted because they provide no unambiguous
complete footprint. Standalone named building ways remain selected.

To bound street detail, service roads, footways, paths, cycleways and living streets
are omitted. Other queried road classes remain actual LineStrings; motorway,
trunk, primary, secondary and tertiary classes (including links) are `primaryRoad`.
Large East Coast Park is omitted because most of it lies outside the neighborhood.
No polygon/road clipping is applied, preserving complete relations and holes.
The retained source is broader than the runtime fixture, so these filters are
reversible without network access.

## Exact offline reproduction

From the repository root:

```sh
python3 Scripts/maps/prepare-fixtures.py
python3 Scripts/maps/prepare-fixtures.py --verify
```

The second command independently checks the stored fixtures' schema, unique IDs,
finite geographic coordinates, closed polygon rings, safe bounded names, total
vertex/file budgets and byte-for-byte agreement with the retained source snapshots.
Sources are gzip-compressed with `mtime=0`; the hashes in `provenance.json` cover
both compressed bytes and original download bytes. No package installation is
needed. This validates data preparation, not renderer appearance or performance.

For a fresh source download (network required; a fresh OSM response may differ):

```sh
curl -L 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/693f11422f4e08d2da4566b854dda53eb7c39fb3/geojson/ne_110m_land.geojson' -o /tmp/world-source.geojson
curl -G 'https://overpass-api.de/api/interpreter' --data-urlencode 'data@Spikes/MapRendering/Fixtures/singapore-query.overpass' -o /tmp/singapore-source.json
```

For historical OSM retrieval on an attic-enabled server, insert
`[date:"2026-10-09T03:27:04Z"]` after `[out:json]` in the retained query. The bundled
snapshot is the authoritative exact-reproduction input; remote response whitespace
and server metadata can change even when historical geometry agrees. Refreshing
snapshots must update fixture hashes and source metadata after verification.
