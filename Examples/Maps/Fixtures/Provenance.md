# Offline vector fixtures

These are real source geometries, retained for the offline map example and adapter tests.
Runtime reads `world.geojson`, `singapore.geojson`, `openfreemap-singapore.pbf`
and their `provenance.json` metadata; it performs no fetch.
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
`103.866`, latitude `1.289`, longitude span approximately `0.030`.

The Singapore fixture and retained raw snapshot are distributed under
[Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
Display **© OpenStreetMap contributors** with
[openstreetmap.org/copyright](https://www.openstreetmap.org/copyright) in the map UI
and derived captures; make its ODbL availability clear. The GeoJSON retains
attribution and license foreign members for inspection. Chio's code license does
not relicense OSM data. The complete transformed database, source snapshot and
conversion script are supplied here for ODbL access and exact reproduction.

## OpenFreeMap vector-tile sample

`openfreemap-singapore.pbf` is the unmodified, uncompressed response for XYZ tile
**14/12919/8133**, from the pinned OpenFreeMap planet build
`20261004_113936_pt`. Its provider-specific geometry is decoded by the Swift
adapter at launch; it is not converted to our GeoJSON schema first.
The retained `openfreemap-tilejson.json` records the provider endpoint and layer
schema advertised at acquisition. The manifest pins both files with SHA-256.
The supported geometry expands to 384 features, 3,365 vertices and two holes;
the shared starting camera lies in this tile's overlap with the Overpass extract.
This eastern sample stays within the spike's existing source budget. The denser
western neighbor exceeds it after multipart expansion; no supported features
are silently dropped from the retained tile to satisfy the limit.

[OpenFreeMap](https://openfreemap.org/) uses the
[OpenMapTiles schema](https://openmaptiles.org/docs/schema/) and OpenStreetMap data.
The data remains available under [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/);
OpenMapTiles' schema design is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Credit **© OpenMapTiles** and **© OpenStreetMap contributors** in maps and captures,
with links to [OpenMapTiles](https://openmaptiles.org/) and
[OpenStreetMap copyright](https://www.openstreetmap.org/copyright).
The UI also credits OpenFreeMap. Chio's MIT license applies to its code, not these
source data. The complete tile response is supplied alongside the adapter.

This is a single tile with fixed source resolution and finite coverage. Buffered
geometry outside its square does not establish availability in neighboring tiles.
The common terminal detail setting changes presentation of this retained tile;
it does not change source zoom, download adjacent tiles or recover omitted data.
It is a schema-interchange proof, not a live provider integration.

To retrieve the pinned response again, while the provider retains that build:

```sh
curl -fL 'https://tiles.openfreemap.org/planet/20261004_113936_pt/14/12919/8133.pbf' -o /tmp/openfreemap-singapore.pbf
```

The bundled bytes are authoritative if that URL later expires. The fixture
verification script checks the response and TileJSON hashes without network I/O;
Swift tests separately exercise decoding, normalization and rendering.

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
trunk and primary classes (including links) are `primaryRoad`. Secondary and
tertiary streets belong to `road`, keeping provider classification separate from
the terminal's detail policy. The abstract presentation can omit these roads and
buildings without deleting them from the fixture.
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
curl -G 'https://overpass-api.de/api/interpreter' --data-urlencode 'data@Examples/Maps/Fixtures/singapore-query.overpass' -o /tmp/singapore-source.json
```

For historical OSM retrieval on an attic-enabled server, insert
`[date:"2026-10-09T03:27:04Z"]` after `[out:json]` in the retained query. The bundled
snapshot is the authoritative exact-reproduction input; remote response whitespace
and server metadata can change even when historical geometry agrees. Refreshing
snapshots must update fixture hashes and source metadata after verification.
