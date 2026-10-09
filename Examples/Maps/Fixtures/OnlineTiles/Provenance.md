# Online replay and acquisition test inputs

Eight complete OpenFreeMap responses are retained at their original XYZ
coordinates. The three **12/3228/2033**, **12/3229/2033** and **12/3230/2033**
responses support the fixed zoom-12 local HTTP recording replay. Five
zoom-14 responses, **14/12917/8133** through **14/12921/8133**, support
normal-resolution model and loader tests for the initial Singapore camera,
adjacent pan, Merlion and Gardens by the Bay selection. No geometry is relocated, filtered or
rewritten in these retained inputs.

The [manifest](manifest.json) records each exact source URL, UTC retrieval time,
byte count and SHA-256 hash. Only HTTP content encoding would be decoded;
these eight responses were delivered uncompressed. The observed endpoint was
`https://tiles.openfreemap.org/planet/20261004_113936_pt/{z}/{x}/{y}.pbf`.
A dated endpoint is not a guarantee that provider bytes are immutable: expired
version paths can serve current data. The bundled hashes identify the actual
inputs.

Acquisition on 2026-10-09 made eight bounded tile requests in two batches:
three zoom-12 responses at 17:58 UTC and five zoom-14 responses at 18:32 UTC.
Each used a 20-second timeout and a 16 MiB decoded-byte ceiling. The zoom-12
batch is 675,107 bytes; the zoom-14 batch is 1,419,737 bytes; the combined
retained size is 2,094,844 bytes. These are small local replay/test fixtures,
not a bulk download or a provider availability guarantee.

Data is distributed under [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
The [OpenMapTiles schema](https://openmaptiles.org/) is credited under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Maps and captures must
credit **OpenFreeMap**, **© OpenMapTiles** and **© OpenStreetMap contributors**,
with links to [OpenFreeMap](https://openfreemap.org/),
[OpenMapTiles](https://openmaptiles.org/) and
[OpenStreetMap copyright](https://www.openstreetmap.org/copyright).
Chio's code license does not relicense these data. The complete responses are
supplied here for inspection and reuse under their data license.

From the repository root, verify all eight inputs without network or a server:

```sh
python3 Scripts/maps/online-fixture-server.py --verify
```

For an explicitly orchestrated recording session:

```sh
python3 Scripts/maps/online-fixture-server.py \
  --config-file .build/maps/online-demo/source.json \
  --ready-file .build/maps/online-demo/ready.json
```

The standard-library Python server binds only `127.0.0.1`, chooses an ephemeral
port, and serves only the eight exact XYZ paths. Other paths receive 404. It
emits one readiness JSON line, writes the source configuration for
`chio-maps --online --tile-source .build/maps/online-demo/source.json`, and does
not log requests. Ctrl-C or SIGTERM closes it. The default 250 ms GET delay makes
loading visible; `--delay-ms 0` removes it. Responses default to `no-store`;
`--cache-seconds 60` enables a small repeatable cache window.

The recording source remains fixed at zoom 12. Its captures replay the three
zoom-12 tiles; they do not demonstrate automatic zoom-14 selection. The five
zoom-14 inputs are separately exercised by the model/acquisition tests with a
normal 0...14 source range. Zooming or panning beyond the configured retained
coverage intentionally fails rather than fetching live data or substituting
invented geometry.

Whole western zoom-14 inputs exceed the canonical feature allowance. Tests
preserve that rejection while independently counting all admitted parts and
holes within each camera's drawing region. The acquired tile list identifies
successful inputs; coverage describes the retained region, not complete geometry
for every acquired tile. Fixture integrity checks establish bytes and provenance;
Swift decoding, rendering, terminal interaction and appearance require separate
integration checks.
