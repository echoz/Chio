@testable import Chio
import Foundation
import Testing

struct MapPolygonAdmissionTests {
    @Test("Every accepted ring participates in spatial admission and preparation", arguments: MapDetail.allCases)
    func visibleSecondaryRing(detail: MapDetail) throws {
        let exterior = try rectangle(10, 10, 12, 12)
        let secondary = try rectangle(-1, -1, 1, 1)
        let polygon = try MapPolygon(rings: [exterior, secondary])
        let decoded = try JSONDecoder().decode(MapPolygon.self, from: JSONEncoder().encode(polygon))
        let request = try request()
        for value in [polygon, decoded] {
            let source = try dataset(value)
            let captured = source
            #expect(try MapPreparation.mayIntersect(.polygon(value), request: request))
            let prepared = try MapPreparation.prepare(dataset: source, camera: request.camera,
                                                       viewport: request.viewport, detail: detail)
            let retained = try #require(prepared.polygons.first)
            #expect(prepared.polygons.count == 1)
            #expect(retained.rings.map(\.count) == [5, 5])
            #expect(retained.rings[1] == secondary.coordinates.map {
                request.viewport.project($0, camera: request.camera)
            })
            #expect(prepared.lines.count == 1)
            #expect(prepared.statistics.visibleFeatures == 1)
            #expect(source == captured)
        }
    }

    @Test("Spatial admission still rejects polygons when every ring is offscreen")
    func offscreenRings() throws {
        let polygon = try MapPolygon(rings: [rectangle(10, 10, 12, 12), rectangle(14, 14, 16, 16)])
        let request = try request()
        #expect(try !MapPreparation.mayIntersect(.polygon(polygon), request: request))
        for detail in MapDetail.allCases {
            let prepared = try MapPreparation.prepare(dataset: dataset(polygon), camera: request.camera,
                                                       viewport: request.viewport, detail: detail)
            #expect(prepared.polygons.isEmpty)
            #expect(prepared.lines.isEmpty)
        }
    }

    @Test("Dateline secondary rings keep their aligned branch across ring start points", arguments: 0..<4)
    func datelineSecondaryRing(start: Int) throws {
        let exterior = try rectangle(165, 10, 170, 12)
        let open = try [coordinate(178, -1), coordinate(-180, -1), coordinate(-180, 1), coordinate(178, 1)]
        let rotated = Array(open[start...]) + Array(open[..<start])
        let secondary = try MapRing(coordinates: rotated + [rotated[0]])
        let polygon = try MapPolygon(rings: [exterior, secondary])
        let camera = try MapCamera(center: coordinate(179, 0), longitudeSpan: 10)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let request = MapTileRequest(camera: camera, viewport: viewport)
        #expect(try MapPreparation.mayIntersect(.polygon(polygon), request: request))
        for detail in MapDetail.allCases {
            let prepared = try MapPreparation.prepare(dataset: dataset(polygon), camera: camera,
                                                       viewport: viewport, detail: detail)
            let retained = try #require(prepared.polygons.first)
            #expect(prepared.polygons.count == 1)
            #expect(retained.rings[1].map(\.x).min() == 40)
            #expect(retained.rings[1].map(\.x).max() == 60)
            #expect(retained.rings[1].count == secondary.coordinates.count)
        }
    }

    @Test("Duplicate secondary rings cannot erase a visible even-odd polygon", arguments: MapDetail.allCases)
    func overlappingHoles(detail: MapDetail) throws {
        let exterior = try rectangle(-1, -1, 1, 1)
        let secondary = try rectangle(-0.9, -0.9, 0.9, 0.9)
        let polygon = try MapPolygon(rings: [exterior, secondary, secondary])
        let request = try request()
        let prepared = try MapPreparation.prepare(dataset: dataset(polygon), camera: request.camera,
                                                   viewport: request.viewport, detail: detail)
        let retained = try #require(prepared.polygons.first)
        #expect(retained.rings.count == 3)
        #expect(retained.rings[1] == retained.rings[2])
    }

    @Test("A self-crossing ring is not discarded using its smaller signed area", arguments: MapDetail.allCases)
    func selfCrossingRing(detail: MapDetail) throws {
        // Two visible lobes, but their opposite winding nearly cancels signed area.
        let ring = try MapRing(coordinates: [coordinate(-0.2, 0.2), coordinate(0.2, -0.2),
                                             coordinate(-0.2, -0.2), coordinate(0.2, 0.18), coordinate(-0.2, 0.2)])
        let request = try request()
        let prepared = try MapPreparation.prepare(dataset: dataset(MapPolygon(rings: [ring])),
                                                   camera: request.camera, viewport: request.viewport, detail: detail)
        #expect(prepared.polygons.count == 1)
    }

    @Test("Topology proof has exact work bounds and preserves its input")
    func topologyProofBudget() throws {
        let ring = [PreparedMap.Point(x: 0, y: 0), PreparedMap.Point(x: 2, y: 0),
                    PreparedMap.Point(x: 2, y: 2), PreparedMap.Point(x: 0, y: 2), PreparedMap.Point(x: 0, y: 0)]
        let captured = ring
        // Four edges require all six unordered edge-pair checks, even adjacent ones.
        var exact = 6
        #expect(try MapShapeSimplification.provesTopology([ring], operationBudget: &exact))
        #expect(exact == 0)
        var short = 5
        #expect(try !MapShapeSimplification.provesTopology([ring], operationBudget: &short))
        #expect(short == 0)
        var empty = 0
        #expect(try !MapShapeSimplification.provesTopology([ring], operationBudget: &empty))
        #expect(empty == 0)
        #expect(ring == captured)
    }

    @Test("Exhausting an admission proof retains a small polygon rather than guessing its topology")
    func unprovenSmallPolygon() throws {
        let points = try (0..<2_048).map { index in
            let angle = Double(index) / 2_048 * 2 * Double.pi
            return try coordinate(cos(angle) * 0.01, sin(angle) * 0.01)
        }
        let polygon = try MapPolygon(rings: [MapRing(coordinates: points + [points[0]])])
        let request = try request()
        let source = try dataset(polygon)
        let captured = source
        for detail in MapDetail.allCases {
            let prepared = try MapPreparation.prepare(dataset: source, camera: request.camera,
                                                       viewport: request.viewport, detail: detail)
            #expect(prepared.polygons.count == 1)
        }
        #expect(source == captured)
    }

    private func request() throws -> MapTileRequest {
        try MapTileRequest(camera: MapCamera(center: coordinate(0, 0), longitudeSpan: 10),
                           viewport: MapViewport(columns: 100, rows: 40))
    }

    private func dataset(_ polygon: MapPolygon) throws -> MapDataset {
        try MapDataset(features: [MapFeature(id: "accepted-rings", kind: .water, geometry: .polygon(polygon))])
    }

    private func rectangle(_ left: Double, _ bottom: Double, _ right: Double, _ top: Double) throws -> MapRing {
        try MapRing(coordinates: [coordinate(left, bottom), coordinate(right, bottom), coordinate(right, top),
                                  coordinate(left, top), coordinate(left, bottom)])
    }

    private func coordinate(_ longitude: Double, _ latitude: Double) throws -> MapCoordinate {
        try MapCoordinate(latitude: latitude, longitude: longitude)
    }
}
