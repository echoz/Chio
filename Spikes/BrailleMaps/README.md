# Braille map visual experiment

An isolated, capture-only comparison. Nothing here is a public Chio style or a
Pitwall integration. `@testable` access reuses Chio's existing projection,
prepared geometry and drawing admission without widening the library API.

The three variants share source data, camera, allocation, detail and route. All
labels are hidden. The baseline uses the shipped area fills, line drawing and
selected-marker glyph. The prototypes use only native Braille dots, with a bright
route, cleared halo and a dot-ring position marker. The textured version adds
sparse area stipples sampled through all polygon rings with even-odd holes.

Native Canvas permits only one foreground per cell. Prototype cells therefore
retain dots of their winning role: position, route, primary road, outline, then
area texture. Other dots are suppressed instead of recolored. Route and marker
halos clear adjacent dots as well as taking ownership of touched cells.

## Comparisons

Each image reads left to right: existing renderer, Braille outlines, then Braille
outlines with sparse textures. Geography, preparation detail, camera, dimensions
and synthetic route are identical within each comparison. All use the default
Chio theme and a physical cell aspect of 2. The baseline retains its selected
diamond; both prototypes use the same 13-dot amber ring and centre dot.

| Scene | Allocation | Comparison | Enlarged detail |
| --- | --- | --- | --- |
| Marina Bay, abstract detail | 96×32 | [Full view](Captures/singapore-comparison.png) | [Route and position](Captures/singapore-detail.png) |
| Same street camera, narrow | 60×24 | [Full view](Captures/singapore-narrow-comparison.png) | [Route and position](Captures/singapore-narrow-detail.png) |
| World, minimal detail | 80×40 | [Full view](Captures/world-comparison.png) | [Europe to Southeast Asia](Captures/world-detail.png) |

These are actual `DefaultRenderer`/native `Canvas` cell exports, converted to PNG
with the existing snapshot tool. Map geometry is not redrawn in Python. Original
panels use 12×24 pixels per cell; detail crops enlarge those pixels exactly 2×.
They establish native masks and RGB cell styles, not emulator/SSH appearance.
Captions and attribution sit outside the captured map allocation.

## Findings

- **Outlines remove the coarse fill edges**, but streets and coasts compete, and
  empty water is harder to distinguish from land. Dense intersections remain busy:
  this experiment changes presentation, not geometry or source detail.
- **Sparse textures are the stronger street-map candidate.** Quiet paired blue
  dots indicate water; staggered green dots indicate parks. They restore some
  geographic context without competing with the bright route. They are faint at
  full-panel size. World land stipples are particularly subtle; continental
  outlines do most of the work there.
- **The cleared route reads more cleanly.** In the actual baseline rasters,
  unrelated geographic dots inherit route pink in 15 cells at 96×32, 11 at 60×24,
  and 21 in the world frame. The prototypes instead remove lower-priority dots
  from those cells; every submitted cell has one role and one foreground.
- **Clearance costs context.** It interrupts coastlines at route crossings and
  hides small details around the position. In the narrow frame the ring appears
  detached from the route endpoint; on the world map it crowds Southeast Asia.
  The amber position is easy to find but needs that space. This is a tradeoff of
  whole-cell colour ownership plus a one-dot halo, not extra subcell colours.

These observations were checked against all three views and enlarged crops,
including an independent visual review. Sparse textures merit another visual
iteration; this experiment does not select a new public default. Motion, texture
anchoring while panning, multiple markers, other themes, indexed colour and
actual terminal fonts remain untested. The texture is currently screen-anchored;
it has no animation, clock or randomness.

## Reproduce

Requires the repository's Swift toolchain, Python 3 with Pillow, and fonts with
Braille coverage. From the repository root:

```sh
bash Spikes/BrailleMaps/capture.sh
```

Set `CHIO_CAPTURE_PYTHON=/path/to/python3` if Pillow is installed in a different
interpreter. The script checks Pillow before building. macOS defaults to Menlo
and Apple Symbols; elsewhere pass `--font /path/to/mono.ttf --symbol-font
/path/to/braille.ttf`. Output is ignored under `.build/braille-map-spike/`,
including raw cell JSON, per-variant PNGs, comparisons and enlarged crops.

The script serially runs only `BrailleMapSpikeTests` in release, then renders the
images. Ordinary test runs exercise the suite without writing captures. Retained
[manifest](Captures/manifest.json) and [metrics](Captures/metrics.json) describe the
committed frames. Source provenance and licenses remain in the existing
[fixture record](../../Examples/Maps/Fixtures/Provenance.md); no network is used.

## Bounds and verification

The prototype reuses `MapPreparation`, `MapDrawingWork.StrokeSegment` and native
`BrailleCanvas`; native `Canvas` still owns terminal glyphs and cells. It introduces
no renderer, projection, source adapter or public style protocol. A test target
under `Spikes/` provides access to Chio internals without changing their visibility.

Texture ownership samples polygon interiors at dot centres. Even-odd crossings
include every ring; holes expose underlying areas, with the shipped area order
(land, park, water, building, roads). Texture candidates, edge visits and sorting
are admitted at the finer grid before painting: 250,000 candidates, two million
edge visits and 16 million sort weight. The existing 250,000 stroke limit remains.
Rejected work produces no partial drawing.

The 240×100 viewport cap bounds ownership and native scratch masks at 192,000
dot positions each. There are seven role masks and two halo masks. Each halo
attempts at most nine writes per lit source dot. Native emission is bounded by
192,000 dots. These are work bounds, not performance guarantees.

Verified on macOS with Swift 6.4:

- All 11 prototype tests pass, checking native masks/colours, no polygon backgrounds,
  subcell holes and winding, water/park ordering, route halo, clipped/overlapping
  position markers, unchanged DDA sampling, thin polygons, and exact/over-limit
  texture candidate, edge and sorting budgets.
- All 46 existing map preparation, drawing-budget, rendering and overlay tests pass.
- Independent source review checked native cell-colour behavior, area ordering
  and bounded work; actual comparison images were inspected separately.

No Linux, interactive PTY, animation or benchmark claim is made for this spike.
The public component, example launch commands and showcase are unchanged.
