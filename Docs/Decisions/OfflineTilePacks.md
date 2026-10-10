# Programmatic offline tile packs

**Status:** Implemented programmatic storage and loading.
[Verification](../Verification.md) defines the required delivery gates.
[Plan](../Plan.md) tracks delivery. [Online acquisition](OnlineMaps.md) owns the
shared loader and HTTP-cache contracts; [geographic maps](GeographicMaps.md)
owns projection, admission and rendering.

## Composition and ownership

Applications create a `MapTilePackPlan` from a nonwrapping `MapCoverage.Bounds`,
source zoom interval and raw-byte ceiling. `MapTilePack.create(at:plan:metadata:tileData:)`
asks the application's async closure for each planned XYZ tile, then publishes
one complete file. The returned actor owns a read-only descriptor. Subsequent
launches use `MapTilePack.open(at:)`; bundled files need no writable directory.
No provider discovery or downloader is hidden in either operation. Applications
own where bytes come from, distribution, credentials and any management UI.

`MapTileLoader(pack:)` fixes one reader for the consumer's lifetime. It reads raw
tiles on demand into the same bounded memory cache used by online acquisition,
then reuses viewport planning, MVT decoding, geometry admission and snapshot
publication. It contains no HTTP transport. Missing pack coverage throws
`MapTileLoader.LoadingError.outsidePackCoverage`; it cannot trigger a network
fallback. A present zero-byte tile is valid empty geometry. An advertised tile
with corrupt or missing bytes is a pack error; checksum-valid malformed MVT
remains a decoder error. Required viewport coverage is never silently truncated.

Memory retains at most 64 entries and 32 MiB. Pack entries do not use HTTP expiry,
receipt times or a fabricated infinite lifetime. Eviction discards only memory
copies, which can later be reread. Pack data is not copied into `MapTileCache`;
the existing writable online cache keeps its expiry, eviction and failure rules.
No shared cache can mix packs merely because their provenance or XYZ addresses
match. Changing packs requires a replacement loader.

Retain the reader until its consumers stop, then call `await pack.close()`.
Closing rejects later loads, including memory hits. Independent readers can open
the same file. Each retains its own descriptor; deletion or path replacement
does not redirect an already-open reader. Published files must not be mutated in
place. The application owns its directories and distribution; checksums detect
accidental corruption, not authenticity or hostile filesystem activity.

## Coverage and bounds

Plans enumerate complete intersecting XYZ tiles at each selected source zoom,
using the same half-open boundary rounding as viewport planning. They count
before enumeration and reject more than 1,024 tiles. Source zooms are 1…22;
zoom 0 has the existing full-world geometry limitation. Longitude bounds cannot
cross the antimeridian; applications must select separate regions for that case.
Latitudes use the existing Mercator clamp. The requested box selects tiles;
complete edge tiles remain available beyond the exact box. Viewport snapshots
still describe their admitted region, not the entire pack's footprint.

The default raw-byte limit is 128 MiB, configurable up to 256 MiB. Each tile is
limited to 16 MiB. Metadata, framing and the index are bounded additional bytes.
These are logical file-length limits, not filesystem allocation guarantees.
The producer is called sequentially, and over-budget responses fail preparation
without publishing a partial pack. The application-supplied producer owns its
own allocation, I/O deadlines and cancellation responsiveness. Chio checks
cancellation around each callback and throughout bounded file/checksum work;
it cannot forcibly interrupt an uncooperative callback or native filesystem call.

The loader clamps requested resolution to available source zooms and retains
its existing at-most-two lower-zoom geometry-budget retries and 16-tile viewport
limit. A pack containing only coarse tiles can still be zoomed into, with coarse
geography; no additional detail is invented.

## Format and publication

Version 1 is a Chio-specific single file: a 40-byte header, contiguous raw tile
payloads, a JSON manifest of at most 16 KiB and a 32-byte index entry per tile.
The manifest retains the checked plan and required source metadata. The index
must exactly match the recomputed plan's canonical addresses, lengths and
contiguous offsets; duplicate, extra, omitted and out-of-range records reject.
File length must match exactly. CRC32 covers header/manifest/index and each tile.
Opening validates the bounded index and metadata; reads verify payload checksums
before handing bytes to the existing decoder. Unsupported versions reject;
there is no implicit migration, repair or data deletion during reading.

Preparation uses an exclusively created sibling temporary. The header remains
invalid until all tiles, metadata and index have been written. Publication
atomically links the completed file at an unoccupied destination, then removes
the temporary name. Existing files and symlinks are never overwritten. Files
are published read-only; readers create no lockfiles or application access records.
Ordinary pre-publication errors and cancellation remove only the owned temporary.
If temporary-name cleanup fails after publication, creation reports an I/O error
while preserving the complete destination; it never rolls back a visible pack.
Abrupt process termination can leave that temporary behind, but it is not a
completed destination and readers do not discover or repair it. This establishes
a process-interruption boundary, not power-loss durability.

PMTiles/MBTiles ingestion, provider archive downloads, resumable preparation and
combined pack/network fallback remain separate work. This format adds no package
dependency and does not resolve the existing static-Linux transport limitations.

## Example and verification

`chio-maps --write-tile-pack PATH` creates a world pack from four retained zoom-1
fixtures and exits. `chio-maps --tile-pack PATH` opens it through the same native
tile view, with an offline label, retained camera/focus and explicit unavailable
coverage. Both are programmatic API examples, not a download-management product.

[Verification](../Verification.md) defines the compiler, storage, hosted-view and
real-process checks. Deterministic fixtures prove local behavior; they do not
establish provider download permission or live archive compatibility.
