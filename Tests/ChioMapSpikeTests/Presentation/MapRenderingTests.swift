@testable import ChioMapSpike
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct MapRenderingTests {
    @Test("Lower detail changes the actual filled coastline while retaining an island hole",
          arguments: [MapFeature.Kind.land, .water])
    func generalizedCoastline(kind: MapFeature.Kind) throws {
        // A shallow bay crosses a cell center: removing it must visibly change
        // the fill, even with no names or labels anywhere in the input.
        let coast: [PreparedMap.Point] = [
            .init(x: 2.2, y: 2.2), .init(x: 7.2, y: 2.2),
            .init(x: 7.2, y: 2.8), .init(x: 9.2, y: 2.8),
            .init(x: 9.2, y: 2.2), .init(x: 18.2, y: 2.2),
            .init(x: 18.2, y: 14.2), .init(x: 2.2, y: 14.2), .init(x: 2.2, y: 2.2),
        ]
        let rings = try [coast, rectangle(12.2, 8.2, 14.2, 10.2)].map { points in
            try MapRing(coordinates: points.map {
                try MapCoordinate(latitude: MapViewport.latitude(mercatorY: (10 - $0.y) * 2),
                                  longitude: $0.x - 20)
            })
        }
        let dataset = try MapDataset(features: [MapFeature(id: "coast", kind: kind,
                                                           geometry: .polygon(MapPolygon(rings: rings)))])
        let viewport = try MapViewport(columns: 40, rows: 20)
        let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 40)
        let exact = try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport, detail: .source)
        let broad = try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport, detail: .silhouette)
        #expect(broad.polygons[0].rings[0].count < exact.polygons[0].rings[0].count)
        #expect(exact.labels.isEmpty && broad.labels.isEmpty)
        for theme in [ChioTheme.default, .light, .btop] {
            let original = try render(exact, columns: 40, rows: 20, theme: theme)
            let generalized = try render(broad, columns: 40, rows: 20, theme: theme)
            let fill = kind == .land ? theme.colors.selectedSurface : waterColor(theme)
            #expect(original.cells[2][7].style?.backgroundColor == theme.colors.surface)
            #expect(generalized.cells[2][7].style?.backgroundColor == fill)
            #expect(original.cells[5][5].style?.backgroundColor == fill)
            #expect(generalized.cells[5][5].style?.backgroundColor == fill)
            #expect(generalized.cells[8][12].style?.backgroundColor == theme.colors.surface)
            let abstract = try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport, detail: .abstract)
            #expect(try render(abstract, columns: 40, rows: 20, theme: theme) == original)
        }
    }

    @Test("Native polygon fills retain holes and underlying area colors in every theme")
    func polygonHoles() throws {
        let water = PreparedMap.Polygon(featureID: "lake", kind: .water,
                                        rings: [rectangle(2, 2, 8, 8), rectangle(4, 4, 6, 6)])
        let land = PreparedMap.Polygon(featureID: "land", kind: .land, rings: [rectangle(0, 0, 10, 10)])
        for theme in [ChioTheme.default, .light, .btop] {
            let surface = try render(map(polygons: [water]), columns: 10, rows: 10, theme: theme)
            #expect(surface.size == CellSize(width: 10, height: 10))
            #expect(surface.cells[2][2].style?.backgroundColor == waterColor(theme))
            #expect(surface.cells[7][7].style?.backgroundColor == waterColor(theme))
            #expect(surface.cells[4][4].style?.backgroundColor == theme.colors.surface)
            #expect(surface.cells[5][5].style?.backgroundColor == theme.colors.surface)
            #expect(surface.cells[1][1].style?.backgroundColor == theme.colors.surface)
            #expect(surface.cells.flatMap { $0 }.filter { $0.style?.backgroundColor == waterColor(theme) }.count == 32)

            // An interior hole exposes the prior land layer rather than repainting it.
            let layered = try render(map(polygons: [water, land]), columns: 10, rows: 10, theme: theme)
            #expect(layered.cells[4][4].style?.backgroundColor == theme.colors.selectedSurface)
            #expect(layered.cells[2][2].style?.backgroundColor == waterColor(theme))
            let outlinesOnly = try render(map(polygons: [water]), columns: 10, rows: 10, theme: theme, fills: false)
            #expect(outlinesOnly.cells.flatMap { $0 }.allSatisfy { $0.style?.backgroundColor == theme.colors.surface })
        }
    }

    @Test("Per-cell area paint priority is independent of supplied feature order")
    func areaPriority() throws {
        let park = PreparedMap.Polygon(featureID: "park", kind: .park, rings: [rectangle(1, 1, 9, 9)])
        let water = PreparedMap.Polygon(featureID: "water", kind: .water, rings: [rectangle(2, 2, 8, 8)])
        let building = PreparedMap.Polygon(featureID: "building", kind: .building, rings: [rectangle(3, 3, 7, 7)])
        for theme in [ChioTheme.default, .light, .btop] {
            let surface = try render(map(polygons: [building, water, park]), columns: 10, rows: 10, theme: theme)
            #expect(surface.cells[1][1].style?.backgroundColor == parkColor(theme))
            #expect(surface.cells[2][2].style?.backgroundColor == waterColor(theme))
            #expect(surface.cells[3][3].style?.backgroundColor == theme.colors.selectedSurface)
            let reordered = try render(map(polygons: [park, building, water]), columns: 10, rows: 10, theme: theme)
            #expect(surface == reordered)
        }
    }

    @Test("A single native Canvas merges braille dots and applies prominent-road cell color")
    func overlappingLines() throws {
        let horizontal = PreparedMap.Line(featureID: "road", kind: .road,
                                          points: [.init(x: 2, y: 4.1), .init(x: 8, y: 4.1)])
        let vertical = PreparedMap.Line(featureID: "primary", kind: .primaryRoad,
                                        points: [.init(x: 4.6, y: 2), .init(x: 4.6, y: 8)])
        let land = PreparedMap.Polygon(featureID: "land", kind: .land, rings: [rectangle(0, 0, 10, 10)])
        for theme in [ChioTheme.default, .light, .btop] {
            let surface = try render(map(lines: [vertical, horizontal], polygons: [land]), columns: 10, rows: 10, theme: theme)
            let crossing = surface.cells[4][4]
            let scalar = try #require(crossing.character.unicodeScalars.first)
            #expect((0x2800...0x28FF).contains(scalar.value))
            let mask = scalar.value - 0x2800
            #expect(mask & 0x01 != 0) // The ordinary road's left-column top dot survives.
            #expect(mask & 0xB8 == 0xB8) // All four prominent-road right-column dots survive.
            #expect(crossing.style?.foregroundColor == theme.colors.foreground)
            #expect(crossing.style?.backgroundColor == theme.colors.selectedSurface)
            #expect(surface.cells[4][2].style?.foregroundColor == theme.colors.mutedText)
            #expect(surface.cells[2][4].style?.foregroundColor == theme.colors.foreground)
            let reordered = try render(map(lines: [horizontal, vertical], polygons: [land]), columns: 10, rows: 10, theme: theme)
            #expect(surface == reordered)
        }
    }

    @Test("Native text label placement rejects collisions, duplicates and edges by stable priority")
    func labelPlacement() {
        let candidates: [PreparedMap.Label] = [
            .init(featureID: "road", kind: .primaryRoad, text: "Main Road", position: .init(x: 10, y: 4)),
            .init(featureID: "lake", kind: .water, text: "Lake", position: .init(x: 10, y: 4)),
            .init(featureID: "duplicate", kind: .water, text: "Lake", position: .init(x: 30, y: 3)),
            .init(featureID: "edge", kind: .park, text: "Edge", position: .init(x: 1, y: 0)),
            .init(featureID: "oversized", kind: .park, text: String(repeating: "x", count: 21), position: .init(x: 20, y: 2)),
            .init(featureID: "far", kind: .road, text: "Far Road", position: .init(x: 30, y: 7)),
        ]
        let positioned = MapLabels(candidates: candidates, columns: 40, rows: 10, enabled: true)
        // Duplicate names use ascending ID within a kind, so "duplicate" wins.
        #expect(positioned.labels.map(\.id) == ["duplicate", "road", "far"])
        #expect(positioned.labels.allSatisfy { $0.column >= 1 && $0.row >= 1 && $0.column + $0.width < 40 && $0.row < 9 })
        #expect(MapLabels(candidates: Array(candidates.reversed()), columns: 40, rows: 10, enabled: true) == positioned)
        #expect(MapLabels(candidates: candidates, columns: 40, rows: 10, enabled: false).labels.isEmpty)
        let collisionOnly = Array(candidates.prefix(2))
        #expect(MapLabels(candidates: collisionOnly, columns: 40, rows: 10, enabled: true).labels.map(\.id) == ["lake"])
    }

    @Test("Native Text preserves wide and combining characters using terminal-cell width")
    func unicodeLabels() throws {
        let text = "界e\u{301}"
        let candidate = PreparedMap.Label(featureID: "unicode", kind: .water, text: text, position: .init(x: 10, y: 4))
        let positioned = MapLabels(candidates: [candidate], columns: 20, rows: 10, enabled: true)
        let label = try #require(positioned.labels.first)
        #expect(label.width == 3 && label.column == 9 && label.row == 4)
        for theme in [ChioTheme.default, .light, .btop] {
            let surface = try render(map(labels: [candidate]), columns: 20, rows: 10, theme: theme, labels: true)
            #expect(surface.lines[4].contains(text))
            #expect(surface.cells[4][9].character == "界" && surface.cells[4][9].spanWidth == 2)
            #expect(surface.cells[4][11].character == "e\u{301}" && surface.cells[4][11].spanWidth == 1)
            #expect(surface.cells[4][9].style?.foregroundColor == theme.colors.foreground)
            #expect(surface.cells[4][9].style?.backgroundColor == theme.colors.surface)
            let hidden = try render(map(labels: [candidate]), columns: 20, rows: 10, theme: theme, labels: false)
            #expect(!hidden.lines.joined().contains(text))
        }
    }

    @Test("Abstract labels leave breathing room and a small allocation-scaled label budget")
    func abstractLabelDensity() {
        let candidates: [PreparedMap.Label] = (0..<20).map { index in
            let column: Int = 10 + (index % 5) * 18
            let row: Int = 2 + (index / 5) * 5
            let position = PreparedMap.Point(x: Double(column), y: Double(row))
            return PreparedMap.Label(featureID: "place-\(index)", kind: .primaryRoad,
                                     text: "Place \(index)", position: position)
        }
        let abstract = MapLabels(candidates: candidates, columns: 100, rows: 20, enabled: true, detail: .abstract)
        let source = MapLabels(candidates: candidates, columns: 100, rows: 20, enabled: true, detail: .source)
        #expect(abstract.labels.count == 6)
        #expect(source.labels.count > abstract.labels.count)
        #expect(MapLabels(candidates: Array(candidates.reversed()), columns: 100, rows: 20,
                          enabled: true, detail: .abstract) == abstract)
        #expect(MapLabels(candidates: candidates, columns: 100, rows: 20,
                          enabled: false, detail: .abstract).labels.isEmpty)
    }

    @Test("A named road crossing the viewport receives a visible native Text label")
    func clippedRoadLabel() throws {
        let source = try MapDataset(features: [MapFeature(id: "road", kind: .road, name: "Road",
                                                          geometry: .polyline(MapPolyline(coordinates: [
                                                            MapCoordinate(latitude: 0, longitude: -50),
                                                            MapCoordinate(latitude: 0, longitude: 50),
                                                          ])))])
        let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 20)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let prepared = try MapPreparation.prepare(dataset: source, camera: camera, viewport: viewport)
        let positioned = MapLabels(candidates: prepared.labels, columns: 100, rows: 40, enabled: true)
        #expect(positioned.labels.map(\.column) == [48])
        #expect(positioned.labels.map(\.row) == [20])
        let surface = try render(prepared, columns: 100, rows: 40, theme: .default, labels: true)
        #expect(surface.lines[20].contains("Road"))
    }

    @Test("Original offscreen fill rings only paint the allocated native cell surface")
    func boundedFill() throws {
        let giant = PreparedMap.Polygon(featureID: "land", kind: .land,
                                        rings: [rectangle(-1_000_000, -1_000_000, 1_000_000, 1_000_000)])
        for (columns, rows) in [(1, 1), (4, 2), (10, 5), (36, 18)] {
            let surface = try render(map(polygons: [giant]), columns: columns, rows: rows, theme: .default)
            #expect(surface.size == CellSize(width: columns, height: rows))
            #expect(surface.cells.count == rows && surface.cells.allSatisfy { $0.count == columns })
            #expect(surface.cells.flatMap { $0 }.allSatisfy { $0.style?.backgroundColor == ChioTheme.default.colors.selectedSurface })
        }
    }

    @Test("Both bundled geographic sources decode and render through the same native map")
    func bundledFixtureSmoke() throws {
        let fixtures = try MapFixtures.load()
        #expect(fixtures.world.features.count == 127 && fixtures.world.vertexCount == 5_143)
        #expect(fixtures.street.features.count == 2_822 && fixtures.street.vertexCount == 20_494)
        for scene in MapFixtures.Scene.allCases {
            let dataset = fixtures.dataset(for: scene)
            let viewport = try MapViewport(columns: 36, rows: 18)
            let prepared = try MapPreparation.prepare(dataset: dataset, camera: scene.camera, viewport: viewport)
            let surface = try render(prepared, columns: viewport.columns, rows: viewport.rows, theme: .default)
            #expect(prepared.statistics.visibleFeatures > 0)
            #expect(prepared.statistics.preparedVertices <= MapLimits.preparedVertices)
            #expect(surface.size == CellSize(width: 36, height: 18))
            #expect(surface.cells.flatMap { $0 }.contains { $0.character != " " })
        }
    }

    @Test("The experimental UI uses a compact summary below its provisional drawing allocation")
    func minimumAllocation() throws {
        let fixtures = try MapFixtures.load()
        for scene in MapFixtures.Scene.allCases {
            for (width, height, isSmall) in [(100, 30, false), (60, 26, false), (60, 20, true), (36, 18, true)] {
                let view = MapSpikeView(fixtures: fixtures, scene: scene, appearance: .default)
                    .environment(\.terminalSize, CellSize(width: width, height: height))
                    .environment(\.cellPixelMetrics, CellPixelMetrics(width: 8, height: 16, source: .estimated))
                let surface = DefaultRenderer().render(view, proposal: .init(width: width, height: height), frameInstant: .zero).rasterSurface
                let text = surface.lines.joined(separator: "\n")
                #expect(surface.size == CellSize(width: width, height: height))
                #expect(text.contains("More room for the map") == isSmall)
                #expect(text.contains("q quit"))
                #expect(text.contains(scene == .world ? "Natural Earth" : "OpenStreetMap contributors"))
                let hasBraille = text.unicodeScalars.contains { (0x2801...0x28FF).contains($0.value) }
                #expect(hasBraille != isSmall)
            }
        }
    }

    @Test("Map UI credits and coverage follow the adapted source rather than the selected scene name")
    func adaptedSourcePresentation() throws {
        let loaded = try MapFixtures.load()
        let swapped = MapFixtures(worldSource: loaded.streetSource, streetSource: loaded.worldSource)
        let view = MapSpikeView(fixtures: swapped, scene: .world, appearance: .default)
            .environment(\.terminalSize, CellSize(width: 100, height: 30))
        let frame = DefaultRenderer().render(view, proposal: .init(width: 100, height: 30), frameInstant: .zero)
        let text = frame.rasterSurface.lines.joined(separator: "\n")
        #expect(text.contains("OpenStreetMap contributors"))
        #expect(text.contains("ODbL 1.0"))
        #expect(text.contains("Outside offline coverage"))
        #expect(!text.contains("Made with Natural Earth"))
    }

    private func render(_ map: PreparedMap, columns: Int, rows: Int, theme: ChioTheme,
                        fills: Bool = true, labels: Bool = false) throws -> RasterSurface {
        let view = MapCanvasView(map: map, viewport: try MapViewport(columns: columns, rows: rows),
                                 theme: theme, fills: fills, labels: labels,
                                 waterColor: waterColor(theme), parkColor: parkColor(theme)).chioTheme(theme)
        return DefaultRenderer().render(view, proposal: .init(width: columns, height: rows), frameInstant: .zero).rasterSurface
    }

    private func map(lines: [PreparedMap.Line] = [], polygons: [PreparedMap.Polygon] = [],
                     labels: [PreparedMap.Label] = []) -> PreparedMap {
        PreparedMap(lines: lines, polygons: polygons, labels: labels,
                    statistics: .init(sourceVertices: 0,
                                      preparedVertices: lines.reduce(0) { $0 + $1.points.count }
                                        + polygons.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } },
                                      visibleFeatures: Set(lines.map(\.featureID) + polygons.map(\.featureID)).count))
    }

    private func rectangle(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> [PreparedMap.Point] {
        [.init(x: left, y: top), .init(x: right, y: top), .init(x: right, y: bottom),
         .init(x: left, y: bottom), .init(x: left, y: top)]
    }

    // Use the demo's supplied colors; expected paint locations are independent rectangles.
    private func waterColor(_ theme: ChioTheme) -> Color { tint(theme.syntax.type, toward: theme.colors.surface, amount: 0.22) }
    private func parkColor(_ theme: ChioTheme) -> Color { tint(theme.syntax.string, toward: theme.colors.surface, amount: 0.16) }

    private func tint(_ color: Color, toward base: Color, amount: Double) -> Color {
        Color(red: base.red + (color.red - base.red) * amount,
              green: base.green + (color.green - base.green) * amount,
              blue: base.blue + (color.blue - base.blue) * amount)
    }
}
