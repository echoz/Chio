@testable import ChioMapSpike
import Chio
import Foundation
import SwiftTUI
import Testing

struct MapDrawingWorkTests {
    @Test("Bundled world and street drawings fit every detail budget at ordinary and maximum allocations")
    func fixtureMatrix() throws {
        let fixtures = try MapFixtures.load()
        for scene in MapFixtures.Scene.allCases {
            let moved = try scene.camera.zoomed(by: 1.4).panned(longitudeFraction: 0.12, latitudeFraction: 0.12)
            for camera in [scene.camera, moved] {
                for detail in MapDetail.allCases {
                    for (columns, rows) in [(100, 30), (60, 20), (240, 100)] {
                        let viewport = try MapViewport(columns: columns, rows: rows)
                        let prepared = try MapPreparation.prepare(dataset: fixtures.dataset(for: scene),
                                                                  camera: camera, viewport: viewport, detail: detail)
                        let accepted = try drawing(prepared, viewport: viewport, fills: true)
                        #expect(accepted.map == prepared)
                        #expect(accepted.work.edgeVisits <= MapDrawingWork.edgeVisitLimit)
                        #expect(accepted.work.crossingSortWeight <= MapDrawingWork.crossingSortWeightLimit)
                        #expect(accepted.work.fillWrites <= MapDrawingWork.fillWriteLimit)
                        #expect(accepted.work.strokeSamples <= MapDrawingWork.strokeSampleLimit)
                    }
                }
            }
        }
    }

    @Test("Fill writes admit the exact limit and reject the complete next polygon")
    func fillBoundary() throws {
        let viewport = try MapViewport(columns: 100, rows: 100)
        let full = polygon(rectangle(0, 0, 100, 100))
        let accepted = map(polygons: Array(repeating: full, count: 25))
        let before = accepted
        let work = try MapDrawingWork(map: accepted, viewport: viewport, fills: true)
        #expect(work.fillWrites == 250_000)
        #expect(work.edgeVisits == 10_000)
        #expect(work.crossingSortWeight == 20_000)
        #expect(accepted == before)
        let excess = map(polygons: accepted.polygons + [polygon(rectangle(0, 0, 1, 1))])
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try drawing(excess, viewport: viewport, fills: true)
        }
        #expect(try drawing(excess, viewport: viewport, fills: false).work.fillWrites == 0)
    }

    @Test("Every stroke includes both endpoints, including repeated path junctions")
    func strokeBoundary() throws {
        let viewport = try MapViewport(columns: 1, rows: 1)
        // Both locations share one sample interval: two writes per segment.
        let points = (0...125_000).map { index in point(index.isMultiple(of: 2) ? 0.1 : 0.2, 0.1) }
        let accepted = map(lines: [line(points)])
        #expect(try MapDrawingWork(map: accepted, viewport: viewport, fills: false).strokeSamples == 250_000)
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try drawing(map(lines: [line(points + [point(0.2, 0.1)])]), viewport: viewport, fills: false)
        }
        let boundary = map(lines: [line([point(-1_000_000, 0), point(1_000_000, 0)])])
        #expect(try MapDrawingWork(map: boundary, viewport: viewport, fills: false).strokeSamples == 3)
    }

    @Test("Few vertices can still request too many full-width native samples")
    func longZigzag() throws {
        let viewport = try MapViewport(columns: 240, rows: 100)
        let points = (0...520).map { index in point(index.isMultiple(of: 2) ? 0 : 240, 50) }
        // Each of the 520 segments requests ceil(239.999 * 2) + 1 = 481 samples.
        #expect(520 * 481 > MapDrawingWork.strokeSampleLimit)
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try drawing(map(lines: [line(points)]), viewport: viewport, fills: false)
        }
    }

    @Test("Edge visits admit their own exact limit and reject the next narrow polygon")
    func edgeBoundary() throws {
        let viewport = try MapViewport(columns: 240, rows: 100)
        // No column center is covered, while all 100 row centers need four edge tests.
        let narrow = polygon(rectangle(0.1, 0, 0.4, 100))
        let accepted = map(polygons: Array(repeating: narrow, count: 5_000))
        let work = try MapDrawingWork(map: accepted, viewport: viewport, fills: true)
        #expect(work.edgeVisits == 2_000_000)
        #expect(work.crossingSortWeight == 4_000_000)
        #expect(work.fillWrites == 0)
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try drawing(map(polygons: accepted.polygons + [narrow]), viewport: viewport, fills: true)
        }
    }

    @Test("Complex rings exceed sort weight even when edge visits and fills fit")
    func crossingSortWeight() throws {
        let viewport = try MapViewport(columns: 240, rows: 100)
        let vertices = (0..<16_384).map { index in
            point(index.isMultiple(of: 2) ? 0.1 : 0.4, index.isMultiple(of: 2) ? 0 : 100)
        }
        let complex = polygon(vertices + [vertices[0]])
        #expect(16_384 * 100 < MapDrawingWork.edgeVisitLimit)
        #expect(16_384 * 14 * 100 > MapDrawingWork.crossingSortWeightLimit)
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try drawing(map(polygons: [complex]), viewport: viewport, fills: true)
        }
    }

    @Test("Bounds include every hole ring and preserve half-open row-center semantics")
    func allRingBounds() throws {
        let viewport = try MapViewport(columns: 10, rows: 10)
        let outsideHole = PreparedMap.Polygon(featureID: "unproved-hole", kind: .water,
                                              rings: [rectangle(1, 1, 3, 3), rectangle(7, 7, 9, 9)])
        let bounds = MapDrawingWork.fillBounds(outsideHole.rings, viewport: viewport)
        #expect(bounds.columns == (1..<9) && bounds.rows == (1..<9))
        let work = try MapDrawingWork(map: map(polygons: [outsideHole]), viewport: viewport, fills: true)
        #expect(work.fillWrites == 64 && work.edgeVisits == 64)
        let centers = MapDrawingWork.fillBounds([rectangle(0.5, 1.5, 3.5, 4.5)], viewport: viewport)
        #expect(centers.columns == (0..<3) && centers.rows == (1..<4))
        let offscreen = polygon(rectangle(-1_000_000, -1_000_000, -1, -1))
        let outside = try MapDrawingWork(map: map(polygons: [offscreen]), viewport: viewport, fills: true)
        #expect(outside.edgeVisits == 0 && outside.crossingSortWeight == 0 && outside.fillWrites == 0)
    }

    @Test("Real checked input can be inexpensive to prepare but overwhelm fill writes")
    func checkedOverlaps() throws {
        let ring = try MapRing(coordinates: [coordinate(-30, -30), coordinate(30, -30),
                                            coordinate(30, 30), coordinate(-30, 30), coordinate(-30, -30)])
        let features = try (0..<4_000).map { index in
            try MapFeature(id: "overlap-\(index)", kind: .land, geometry: .polygon(MapPolygon(rings: [ring])))
        }
        let dataset = try MapDataset(features: features)
        let viewport = try MapViewport(columns: 240, rows: 100)
        let prepared = try MapPreparation.prepare(dataset: dataset,
                                                  camera: MapCamera(center: coordinate(0, 0), longitudeSpan: 20),
                                                  viewport: viewport)
        #expect(prepared.polygons.count == 4_000)
        #expect(prepared.statistics.preparedVertices < MapLimits.preparedVertices)
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try drawing(prepared, viewport: viewport, fills: true)
        }
    }

    @Test("Malformed projected geometry is rejected before any native draw")
    func invalidGeometry() throws {
        let viewport = try MapViewport(columns: 10, rows: 10)
        #expect(throws: MapValidationError.invalidPath) {
            try drawing(map(lines: [line([point(.nan, 0), point(1, 1)])]), viewport: viewport, fills: false)
        }
        #expect(throws: MapValidationError.invalidRing) {
            try drawing(map(polygons: [polygon([point(0, 0), point(.infinity, 0), point(1, 1), point(0, 0)])]),
                        viewport: viewport, fills: true)
        }
        #expect(throws: MapValidationError.invalidRing) {
            try drawing(map(polygons: [polygon([point(0, 0), point(1, 0), point(1, 1), point(0, 1)])]),
                        viewport: viewport, fills: true)
        }
    }

    @Test("Finite extreme bounds clamp before integer conversion and statistics cannot bypass checks")
    func extremeBounds() throws {
        let viewport = try MapViewport(columns: 10, rows: 10)
        let magnitude = Double.greatestFiniteMagnitude
        let giant = polygon(rectangle(-magnitude, -magnitude, magnitude, magnitude))
        let work = try MapDrawingWork(map: map(polygons: [giant]), viewport: viewport, fills: true)
        #expect(work.fillWrites == 100 && work.edgeVisits == 40)
        let manyEmptyRings = PreparedMap.Polygon(featureID: "metadata", kind: .land,
                                                rings: Array(repeating: [], count: MapLimits.preparedVertices + 1))
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try drawing(map(polygons: [manyEmptyRings]), viewport: viewport, fills: false)
        }
    }

    private func drawing(_ map: PreparedMap, viewport: MapViewport, fills: Bool) throws -> MapDrawing {
        let colors = ChioTheme.default.colors
        return try MapDrawing(map: map, viewport: viewport, colors: colors,
                              waterColor: colors.selectedSurface, parkColor: colors.selectedSurface, fills: fills)
    }

    private func map(lines: [PreparedMap.Line] = [], polygons: [PreparedMap.Polygon] = []) -> PreparedMap {
        PreparedMap(lines: lines, polygons: polygons, labels: [],
                    statistics: .init(sourceVertices: 0, preparedVertices: 0, visibleFeatures: 0))
    }

    private func line(_ points: [PreparedMap.Point]) -> PreparedMap.Line {
        .init(featureID: "line", kind: .road, points: points)
    }

    private func polygon(_ points: [PreparedMap.Point]) -> PreparedMap.Polygon {
        .init(featureID: "polygon", kind: .land, rings: [points])
    }

    private func rectangle(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> [PreparedMap.Point] {
        [point(left, top), point(right, top), point(right, bottom), point(left, bottom), point(left, top)]
    }

    private func point(_ x: Double, _ y: Double) -> PreparedMap.Point { .init(x: x, y: y) }

    private func coordinate(_ longitude: Double, _ latitude: Double) throws -> MapCoordinate {
        try MapCoordinate(latitude: latitude, longitude: longitude)
    }
}
