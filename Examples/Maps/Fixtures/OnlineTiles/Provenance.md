# Online replay and acquisition test inputs

Twelve complete OpenFreeMap responses are retained at their original XYZ
coordinates. The four zoom-1 tiles, **1/0/0**, **1/0/1**, **1/1/0** and **1/1/1**,
cover the world. The three **12/3228/2033**, **12/3229/2033** and **12/3230/2033**
responses support the street portion of the local HTTP recording replay. Five
zoom-14 responses, **14/12917/8133** through **14/12921/8133**, support
normal-resolution model and loader tests for the initial Singapore camera,
adjacent pan, Merlion and Gardens by the Bay selection. No geometry is relocated, filtered or
rewritten in these retained inputs.

The [manifest](manifest.json) records each exact source URL, UTC retrieval time,
byte count and SHA-256 hash. Only HTTP content encoding would be decoded;
the original eight street responses were delivered uncompressed. Coarse-world
entries record the decoded bytes used by the adapter. The observed endpoint was
`https://tiles.openfreemap.org/planet/20261004_113936_pt/{z}/{x}/{y}.pbf`.
A dated endpoint is not a guarantee that provider bytes are immutable: expired
version paths can serve current data. The bundled hashes identify the actual
inputs.

Retained responses were acquired on 2026-10-09 in three bounded batches:
three zoom-12 responses at 17:58 UTC, five zoom-14 responses at 18:32 UTC,
and four zoom-1 responses at 20:46 UTC.
Each used a 20-second timeout and a 16 MiB decoded-byte ceiling. The zoom-12
batch is 675,107 bytes; the zoom-14 batch is 1,419,737 bytes; the combined
street size is 2,094,844 bytes. The world batch adds 811,607 bytes, for a total
of 2,906,451 bytes. Separate zoom-0/zoom-2 investigation requests are not retained
in this replay corpus. These are small local replay/test fixtures,
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

From the repository root, verify all twelve inputs without network or a server:

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
port, and serves only the twelve exact XYZ paths. Other paths receive 404. It
emits one readiness JSON line, writes the source configuration for
`chio-maps --online --tile-source .build/maps/online-demo/source.json`, and does
not log requests. Ctrl-C or SIGTERM closes it. The default 250 ms GET delay makes
loading visible; `--delay-ms 0` removes it. Responses default to `no-store`;
`--cache-seconds 60` enables a small repeatable cache window.

The recording source advertises zoom 1…12. World views request all four zoom-1
tiles; the Singapore camera requests retained zoom-12 tiles. Intermediate zooms
and locations without a retained exact response deliberately return 404. The
replay is a deterministic world/street workflow, not a complete offline atlas.
The five zoom-14 inputs are separately exercised by model/acquisition tests with
a normal 0…14 source range. No missing response is replaced with live data or
invented geometry.

Whole western zoom-14 inputs exceed the canonical feature allowance. Tests
preserve that rejection while independently counting all admitted parts and
holes within each camera's drawing region. The acquired tile list identifies
successful inputs; coverage describes the retained region, not complete geometry
for every acquired tile. Fixture integrity checks establish bytes and provenance;
Swift decoding, rendering, terminal interaction and appearance require separate
integration checks.
