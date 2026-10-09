@testable import ChioMapSpike
import Foundation
import Testing

struct MapPreparationTests {
    @Test("Projection matches independent Mercator values and physical cell aspect")
    func projectionAndAspect() throws {
        let camera = try MapCamera(center: coordinate(0, 0), longitudeSpan: 100)
        let tall = try MapViewport(columns: 100, rows: 40, cellAspectRatio: 2)
        let square = try MapViewport(columns: 100, rows: 40, cellAspectRatio: 1)
        let position = try coordinate(10, 45)
        let point = tall.project(position, camera: camera)
        #expect(abs(point.x - 60) < 1e-9)
        #expect(abs(point.y - -5.2494933552631) < 1e-9)
        #expect(abs(square.project(position, camera: camera).y - -30.4989867105262) < 1e-9)
        #expect(tall.project(camera.center, camera: camera) == .init(x: 50, y: 20))
        #expect(tall.project(try coordinate(0, 90), camera: camera) == tall.project(try coordinate(0, MapLimits.mercatorLatitude), camera: camera))
        let tiny = try MapCamera(center: coordinate(179, 80), longitudeSpan: MapLimits.minimumLongitudeSpan)
        let distant = tall.project(try coordinate(-100, -90), camera: tiny)
        #expect(distant.x.isFinite && distant.y.isFinite)
    }

    @Test("Dateline paths follow the short branch and split at world viewport edges")
    func dateline() throws {
        let dataset = try line([coordinate(178, 0), coordinate(-178, 0)])
        let viewport = try MapViewport(columns: 100, rows: 40)
        let local = try MapPreparation.prepare(dataset: dataset,
                                               camera: MapCamera(center: coordinate(179, 0), longitudeSpan: 20), viewport: viewport)
        #expect(local.lines.count == 1)
        #expect(local.lines[0].points.first == .init(x: 45, y: 20))
        #expect(local.lines[0].points.last == .init(x: 65, y: 20))
        let world = try MapPreparation.prepare(dataset: dataset,
                                               camera: MapCamera(center: coordinate(0, 0), longitudeSpan: 360), viewport: viewport)
        #expect(world.lines.count == 2)
        #expect(world.lines.allSatisfy { abs($0.points.last!.x - $0.points.first!.x) < 1 })
        #expect(world.lines.contains { $0.points.first?.x == 0 })
        #expect(world.lines.contains { $0.points.last?.x == 100 })
    }

    @Test("Preparation clips crossing lines before native drawing and culls entirely offscreen paths")
    func clipping() throws {
        let camera = try MapCamera(center: coordinate(0, 0), longitudeSpan: 20)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let crossingShort = try line([coordinate(-50, 0), coordinate(50, 0)])
        let prepared = try MapPreparation.prepare(dataset: crossingShort, camera: camera, viewport: viewport)
        #expect(prepared.lines.count == 1)
        #expect(prepared.lines[0].points == [.init(x: 0, y: 20), .init(x: 100, y: 20)])
        let outside = try MapPreparation.prepare(dataset: line([coordinate(-1, 70), coordinate(1, 70)]), camera: camera, viewport: viewport)
        #expect(outside.lines.isEmpty && outside.labels.isEmpty && outside.statistics.visibleFeatures == 0)
        #expect(crossingShort.features[0].geometry.vertexCount == 2)
    }

    @Test("Line detail reduction preserves endpoints and adapts to scale")
    func simplification() throws {
        let coordinates = try (0...200).map { try coordinate(Double($0) / 200, 0) }
        let dataset = try line(coordinates)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let coarse = try MapPreparation.prepare(dataset: dataset,
                                                camera: MapCamera(center: coordinate(0.5, 0), longitudeSpan: 100), viewport: viewport)
        let fine = try MapPreparation.prepare(dataset: dataset,
                                              camera: MapCamera(center: coordinate(0.5, 0), longitudeSpan: 2), viewport: viewport)
        #expect(coarse.lines[0].points.first == .init(x: 49.5, y: 20))
        #expect(coarse.lines[0].points.last == .init(x: 50.5, y: 20))
        #expect(coarse.statistics.preparedVertices < fine.statistics.preparedVertices)
        #expect(coarse.statistics.preparedVertices <= 6)
        #expect(dataset.vertexCount == 201)
    }

    @Test("Polygon hole rings retain every source vertex; outlines are clipped independently")
    func holesAndOutlines() throws {
        let exterior = try MapRing(coordinates: [coordinate(-10, -10), coordinate(10, -10), coordinate(10, 10), coordinate(-10, 10), coordinate(-10, -10)])
        let hole = try MapRing(coordinates: [coordinate(-2, -2), coordinate(-2, 2), coordinate(2, 2), coordinate(2, -2), coordinate(-2, -2)])
        let dataset = try MapDataset(features: [MapFeature(id: "lake", kind: .water, name: "Lake", geometry: .polygon(MapPolygon(rings: [exterior, hole])))])
        let prepared = try MapPreparation.prepare(dataset: dataset,
                                                  camera: MapCamera(center: coordinate(0, 0), longitudeSpan: 30),
                                                  viewport: MapViewport(columns: 100, rows: 40))
        #expect(prepared.polygons.count == 1)
        #expect(prepared.polygons[0].rings.map(\.count) == [5, 5])
        #expect(!prepared.lines.isEmpty)
        #expect(prepared.lines.allSatisfy { $0.featureID == "lake" && $0.points.allSatisfy { $0.x >= 0 && $0.x <= 100 && $0.y >= 0 && $0.y <= 40 } })
        #expect(prepared.labels.isEmpty) // The centroid lies in the hole.
        #expect(prepared.statistics.visibleFeatures == 1)
        #expect(dataset.features[0].geometry.vertexCount == 10)
    }

    @Test("World polar-cap rings preserve their explicit full-width longitude cut", arguments: [MapDetail.source, .abstract])
    func polarCap(detail: MapDetail) throws {
        let ring = try MapRing(coordinates: [coordinate(-180, -90), coordinate(180, -90), coordinate(180, -80), coordinate(0, -80), coordinate(-180, -80), coordinate(-180, -90)])
        let dataset = try MapDataset(features: [MapFeature(id: "antarctica", kind: .land, geometry: .polygon(MapPolygon(rings: [ring])))])
        let prepared = try MapPreparation.prepare(dataset: dataset,
                                                  camera: MapCamera(center: coordinate(0, -75), longitudeSpan: 360),
                                                  viewport: MapViewport(columns: 100, rows: 40), detail: detail)
        let polygon = try #require(prepared.polygons.first { $0.rings[0][0].x == 0 })
        #expect(polygon.rings[0][1].x == 100)
        #expect(polygon.rings[0].first == polygon.rings[0].last)
    }

    @Test("A full-width polar strip keeps its source longitude cut even when shortest unwrap closes", arguments: [MapDetail.source, .abstract])
    func polarStrip(detail: MapDetail) throws {
        let ring = try MapRing(coordinates: [coordinate(-180, -90), coordinate(180, -90),
                                            coordinate(180, -80), coordinate(-180, -80), coordinate(-180, -90)])
        let dataset = try MapDataset(features: [MapFeature(id: "strip", kind: .land,
                                                           geometry: .polygon(MapPolygon(rings: [ring])))])
        let prepared = try MapPreparation.prepare(dataset: dataset,
                                                  camera: MapCamera(center: coordinate(0, -75), longitudeSpan: 360),
                                                  viewport: MapViewport(columns: 100, rows: 40), detail: detail)
        let polygon = try #require(prepared.polygons.first { $0.rings[0][0].x == 0 })
        #expect(polygon.rings[0].map(\.x) == [0, 100, 100, 0, 0])
        #expect(polygon.rings[0][0].y > polygon.rings[0][2].y)
    }

    @Test("Ordinary dateline polygons retain a short longitude branch and all hole rings", arguments: [MapDetail.source, .abstract])
    func datelinePolygon(detail: MapDetail) throws {
        let ring = try MapRing(coordinates: [coordinate(178, -2), coordinate(-178, -2),
                                            coordinate(-178, 2), coordinate(178, 2), coordinate(178, -2)])
        let hole = try MapRing(coordinates: [coordinate(179, -1), coordinate(-179, -1),
                                            coordinate(-179, 1), coordinate(179, 1), coordinate(179, -1)])
        let dataset = try MapDataset(features: [MapFeature(id: "dateline", kind: .land,
                                                           geometry: .polygon(MapPolygon(rings: [ring, hole])))])
        let prepared = try MapPreparation.prepare(dataset: dataset,
                                                  camera: MapCamera(center: coordinate(179, 0), longitudeSpan: 20),
                                                  viewport: MapViewport(columns: 100, rows: 40), detail: detail)
        #expect(prepared.polygons.count == 1)
        #expect(prepared.polygons[0].rings[0].map(\.x) == [45, 65, 65, 45, 45])
        #expect(prepared.polygons[0].rings[1].map(\.x) == [50, 60, 60, 50, 50])
    }

    @Test("Named clipped roads use a visible arclength midpoint, including two-point crossings")
    func visibleLineLabel() throws {
        let camera = try MapCamera(center: coordinate(0, 0), longitudeSpan: 20)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let prepared = try MapPreparation.prepare(dataset: line([coordinate(-50, 0), coordinate(50, 0)]),
                                                  camera: camera, viewport: viewport)
        #expect(prepared.lines[0].points == [.init(x: 0, y: 20), .init(x: 100, y: 20)])
        #expect(prepared.labels.map(\.position) == [.init(x: 50, y: 20)])
        let unequal = try MapPreparation.prepare(dataset: line([coordinate(-10, 0), coordinate(-9, 0), coordinate(10, 0)]),
                                                 camera: camera, viewport: viewport)
        #expect(unequal.labels.map(\.position) == [.init(x: 50, y: 20)])
    }

    @Test("Empty prepared snapshots have zero work and preserve source values")
    func emptyAndPurity() throws {
        let dataset = try MapDataset(features: [])
        let camera = try MapCamera(center: coordinate(0, 0), longitudeSpan: 360)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let prepared = try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport)
        #expect(prepared.lines.isEmpty && prepared.polygons.isEmpty && prepared.labels.isEmpty)
        #expect(prepared.statistics == .init(sourceVertices: 0, preparedVertices: 0, visibleFeatures: 0))
        #expect(try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport) == prepared)
    }

    private func coordinate(_ longitude: Double, _ latitude: Double) throws -> MapCoordinate {
        try MapCoordinate(latitude: latitude, longitude: longitude)
    }

    private func line(_ coordinates: [MapCoordinate]) throws -> MapDataset {
        try MapDataset(features: [MapFeature(id: "road", kind: .road, name: "Road", geometry: .polyline(MapPolyline(coordinates: coordinates)))])
    }
}
