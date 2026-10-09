@testable import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
struct BrailleMapSpikeTests {
    @Test("Capture equal geography, cameras and allocations through the actual native rasterizer")
    func nativeComparisons() throws {
        let comparisons = try BrailleMapCapture.comparisons()
        for comparison in comparisons {
            let size = CellSize(width: comparison.scene.width, height: comparison.scene.height)
            #expect(comparison.existing.size == size)
            for (drawing, raster) in [(comparison.outlineDrawing, comparison.outlines),
                                      (comparison.textureDrawing, comparison.textured)] {
                #expect(raster.size == size)
                #expect(drawing.cells.contains { $0.role == .route })
                #expect(drawing.cells.contains { $0.role == .position })
                for cell in raster.cells.flatMap({ $0 }) {
                    #expect(cell.character == " " || BrailleMapCapture.mask(cell.character) != 0)
                    #expect(cell.style?.backgroundColor == ChioTheme.default.colors.surface)
                }
                // The actual native mask/style must equal the single role submitted.
                for cell in drawing.cells {
                    let rendered = raster.cells[cell.row][cell.column]
                    #expect(BrailleMapCapture.mask(rendered.character) == cell.dots.mask)
                    #expect(rendered.style?.foregroundColor == cell.role.color)
                }
                #expect(drawing.statistics.haloSamples <= 2 * 9 * 8 * size.width * size.height)
            }
            #expect(comparison.textureDrawing.cells.contains { $0.role == .landTexture || $0.role == .waterTexture })
        }
        #expect(comparisons.contains { $0.baselineRouteCollisionCells > 0 })
        if let path = ProcessInfo.processInfo.environment["CHIO_BRAILLE_CAPTURE_DIR"], !path.isEmpty {
            try BrailleMapCapture.write(comparisons, to: URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    @Test("Dot-centre even-odd holes expose the lower area, including sub-cell holes")
    func polygonHoles() throws {
        let viewport = try MapViewport(columns: 12, rows: 6)
        let land = PreparedMap.Polygon(featureID: "land", kind: .land, rings: [rectangle(0, 0, 12, 6)])
        // Water otherwise owns every cell, but a sub-cell hole exposes a land dot at (6.75, 1.375).
        let water = PreparedMap.Polygon(featureID: "water", kind: .water,
                                        rings: [rectangle(0, 0, 12, 6), rectangle(6.5, 1.25, 7, 1.5)])
        let drawing = try BrailleMapDrawing(map: map(polygons: [land, water]), routes: [], viewport: viewport,
                                            position: nil, treatment: .textured)
        let raster = BrailleMapCapture.render(drawing, viewport: viewport)
        #expect(BrailleMapCapture.mask(raster.cells[1][6].character) == 0x10) // Right column, second dot.
        #expect(raster.cells[1][6].style?.foregroundColor == BrailleMapDrawing.Role.landTexture.color)
        #expect(BrailleMapCapture.mask(raster.cells[0][4].character) == 0x24) // Two horizontal water dots.
        #expect(BrailleMapCapture.mask(raster.cells[1][2].character) == 0) // Land stipple submerged by water.
        let reversed = PreparedMap.Polygon(featureID: "water", kind: .water, rings: water.rings.map { Array($0.reversed()) })
        let other = try BrailleMapDrawing(map: map(polygons: [land, reversed]), routes: [], viewport: viewport,
                                          position: nil, treatment: .textured)
        #expect(drawing.cells == other.cells)
    }

    @Test("Route cells have exact route dots, cleared adjacent halo and no recolored coast dots")
    func routeHalo() throws {
        let viewport = try MapViewport(columns: 10, rows: 6)
        let coast = PreparedMap.Line(featureID: "coast", kind: .water,
                                     points: [PreparedMap.Point(x: 0, y: 2.1), PreparedMap.Point(x: 9, y: 2.1)])
        let route = PreparedMap.Line(featureID: "route", kind: .primaryRoad,
                                     points: [PreparedMap.Point(x: 4.6, y: 0), PreparedMap.Point(x: 4.6, y: 5.9)])
        let drawing = try BrailleMapDrawing(map: map(lines: [coast]), routes: [route], viewport: viewport,
                                            position: nil, treatment: .outlines)
        let raster = BrailleMapCapture.render(drawing, viewport: viewport)
        #expect(BrailleMapCapture.mask(raster.cells[2][4].character) == 0xB8) // Only right-column route dots.
        #expect(raster.cells[2][4].style?.foregroundColor == ChioTheme.default.colors.accent)
        #expect(BrailleMapCapture.mask(raster.cells[2][5].character) == 0x08) // Near dot cleared; far coast dot survives.
        #expect(BrailleMapCapture.mask(raster.cells[2][3].character) == 0x09)
        #expect(drawing.statistics.mixedCellsBeforeResolution == 1)
    }

    @Test("Overlapping water stays above parks just as in the existing renderer")
    func waterAbovePark() throws {
        let viewport = try MapViewport(columns: 12, rows: 6)
        let park = PreparedMap.Polygon(featureID: "park", kind: .park, rings: [rectangle(0, 0, 12, 6)])
        let water = PreparedMap.Polygon(featureID: "water", kind: .water, rings: park.rings)
        for polygons in [[water, park], [park, water]] {
            let drawing = try BrailleMapDrawing(map: map(polygons: polygons), routes: [], viewport: viewport,
                                                position: nil, treatment: .textured)
            let raster = BrailleMapCapture.render(drawing, viewport: viewport)
            #expect(BrailleMapCapture.mask(raster.cells[0][4].character) == 0x24)
            #expect(raster.cells[0][4].style?.foregroundColor == BrailleMapDrawing.Role.waterTexture.color)
            #expect(drawing.cells.allSatisfy { $0.role == .waterTexture })
        }
    }

    @Test("A position glyph uses only native dots and owns the cells it occupies")
    func positionGlyph() throws {
        let viewport = try MapViewport(columns: 10, rows: 6)
        let drawing = try BrailleMapDrawing(map: map(), routes: [], viewport: viewport,
                                            position: PreparedMap.Point(x: 5, y: 3), treatment: .outlines)
        #expect(drawing.cells.allSatisfy { $0.role == .position })
        #expect(drawing.cells.reduce(0) { $0 + $1.dots.mask.nonzeroBitCount } == 13)
        let raster = BrailleMapCapture.render(drawing, viewport: viewport)
        #expect(raster.cells.flatMap({ $0 }).filter { BrailleMapCapture.mask($0.character) != 0 }.count == drawing.cells.count)
    }

    @Test("Position dots displace intersecting routes and clip at the viewport edge")
    func markerOverRoute() throws {
        let viewport = try MapViewport(columns: 10, rows: 6)
        let route = PreparedMap.Line(featureID: "route", kind: .primaryRoad,
                                    points: [PreparedMap.Point(x: 0, y: 0), PreparedMap.Point(x: 9.9, y: 5.9)])
        for point in [PreparedMap.Point(x: 5, y: 3), PreparedMap.Point(x: 0, y: 0)] {
            let marker = try BrailleMapDrawing(map: map(), routes: [], viewport: viewport,
                                               position: point, treatment: .outlines)
            let combined = try BrailleMapDrawing(map: map(), routes: [route], viewport: viewport,
                                                 position: point, treatment: .outlines)
            let raster = BrailleMapCapture.render(combined, viewport: viewport)
            for cell in marker.cells {
                #expect(BrailleMapCapture.mask(raster.cells[cell.row][cell.column].character) == cell.dots.mask)
                #expect(raster.cells[cell.row][cell.column].style?.foregroundColor == ChioTheme.default.colors.warning)
            }
            #expect(combined.cells.contains { $0.role == .route })
            #expect(combined.cells.allSatisfy { $0.column >= 0 && $0.column < 10 && $0.row >= 0 && $0.row < 6 })
        }
    }

    @Test("Prototype routes preserve the existing native DDA masks")
    func sameRouteSampling() throws {
        let viewport = try MapViewport(columns: 10, rows: 6)
        let route = PreparedMap.Line(featureID: "route", kind: .primaryRoad,
                                    points: [PreparedMap.Point(x: -2, y: 0), PreparedMap.Point(x: 9.9, y: 0),
                                             PreparedMap.Point(x: 9.9, y: 6), PreparedMap.Point(x: 0.1, y: 0.2)])
        let theme = ChioTheme.default
        let original = try MapDrawing(map: map(), viewport: viewport, colors: theme.colors,
                                       waterColor: theme.map.water, parkColor: theme.map.park, fills: false, routes: [route])
        let experiment = try BrailleMapDrawing(map: map(), routes: [route], viewport: viewport,
                                               position: nil, treatment: .outlines)
        let baseline = BrailleMapCapture.render(original, viewport: viewport)
        let raster = BrailleMapCapture.render(experiment, viewport: viewport)
        #expect(raster.cells == baseline.cells)
    }

    @Test("Dot fill budget admits its exact limit and rejects the next overlapping polygon")
    func textureBudget() throws {
        let viewport = try MapViewport(columns: 125, rows: 50) // 50,000 dot candidates per rectangle.
        let polygon = PreparedMap.Polygon(featureID: "land", kind: .land, rings: [rectangle(0, 0, 125, 50)])
        let accepted = try BrailleMapDrawing(map: map(polygons: Array(repeating: polygon, count: 5)),
                                             routes: [], viewport: viewport, position: nil, treatment: .textured)
        #expect(accepted.statistics.textureCandidates == 250_000)
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try BrailleMapDrawing(map: map(polygons: Array(repeating: polygon, count: 6)),
                                  routes: [], viewport: viewport, position: nil, treatment: .textured)
        }
        let unfilled = try BrailleMapDrawing(map: map(polygons: Array(repeating: polygon, count: 6)),
                                             routes: [], viewport: viewport, position: nil, treatment: .outlines)
        #expect(unfilled.statistics.textureCandidates == 0)
    }

    @Test("Thin polygons missed by cell-centre fills still consume texture work")
    func thinPolygonBudget() throws {
        let viewport = try MapViewport(columns: 100, rows: 2)
        let thin = PreparedMap.Polygon(featureID: "thin", kind: .water, rings: [rectangle(0, 0.51, 100, 0.99)])
        #expect(try MapDrawingWork(map: map(polygons: [thin]), viewport: viewport, fills: true).fillWrites == 0)
        let drawing = try BrailleMapDrawing(map: map(polygons: [thin]), routes: [], viewport: viewport,
                                            position: nil, treatment: .textured)
        #expect(drawing.statistics.textureCandidates == 400)
        #expect(drawing.statistics.textureEdgeVisits == 8)
    }

    @Test("Texture edge visits admit the exact limit independently of fill candidates")
    func textureEdgeBudget() throws {
        let viewport = try MapViewport(columns: 10, rows: 100)
        // Between dot columns: zero candidates, 400 dot rows × four edges each.
        let narrow = PreparedMap.Polygon(featureID: "narrow", kind: .water, rings: [rectangle(0.05, 0, 0.2, 100)])
        let polygons = Array(repeating: narrow, count: 1_250)
        let drawing = try BrailleMapDrawing(map: map(polygons: polygons), routes: [], viewport: viewport,
                                            position: nil, treatment: .textured)
        #expect(drawing.statistics.textureEdgeVisits == 2_000_000)
        #expect(drawing.statistics.textureSortWeight == 4_000_000)
        #expect(drawing.statistics.textureCandidates == 0)
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try BrailleMapDrawing(map: map(polygons: polygons + [narrow]), routes: [], viewport: viewport,
                                  position: nil, treatment: .textured)
        }
    }

    @Test("Texture sort weight admits its exact limit while edge and candidate work fit")
    func textureSortBudget() throws {
        let viewport = try MapViewport(columns: 10, rows: 100)
        func complexRing(height: Double) -> PreparedMap.Polygon {
            // Adversarial overlapping edges, all between dot columns.
            let points = (0..<512).map { index in
                PreparedMap.Point(x: index.isMultiple(of: 2) ? 0.05 : 0.2,
                                  y: index.isMultiple(of: 2) ? 0 : height)
            }
            return PreparedMap.Polygon(featureID: "complex", kind: .water, rings: [points + [points[0]]])
        }
        // (8 × 400 + 272) rows × 512 edges × 9 sort levels, plus 128 × 4 × 2.
        let polygons = Array(repeating: complexRing(height: 100), count: 8)
            + [complexRing(height: 68), PreparedMap.Polygon(featureID: "remainder", kind: .water,
                                                           rings: [rectangle(0.05, 0, 0.2, 32)])]
        let drawing = try BrailleMapDrawing(map: map(polygons: polygons), routes: [], viewport: viewport,
                                            position: nil, treatment: .textured)
        #expect(drawing.statistics.textureSortWeight == 16_000_000)
        #expect(drawing.statistics.textureEdgeVisits == 1_778_176)
        #expect(drawing.statistics.textureCandidates == 0)
        let extra = PreparedMap.Polygon(featureID: "extra", kind: .water, rings: [rectangle(0.05, 0, 0.2, 0.25)])
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try BrailleMapDrawing(map: map(polygons: polygons + [extra]), routes: [], viewport: viewport,
                                  position: nil, treatment: .textured)
        }
    }

    private func map(lines: [PreparedMap.Line] = [], polygons: [PreparedMap.Polygon] = []) -> PreparedMap {
        PreparedMap(lines: lines, polygons: polygons, labels: [],
                    statistics: PreparedMap.Statistics(sourceVertices: 0, preparedVertices: 0, visibleFeatures: 0))
    }

    private func rectangle(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [PreparedMap.Point] {
        [PreparedMap.Point(x: x0, y: y0), PreparedMap.Point(x: x1, y: y0),
         PreparedMap.Point(x: x1, y: y1), PreparedMap.Point(x: x0, y: y1), PreparedMap.Point(x: x0, y: y0)]
    }
}
