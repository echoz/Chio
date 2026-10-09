@testable import ChioMapSpike
import Foundation
import Testing

struct MapDetailTests {
    @Test("Abstract maps omit buildings and admit minor roads only at useful scale and allocation")
    func scaleAndAllocation() throws {
        let minor = try road("minor", kind: .road)
        let major = try road("major", kind: .primaryRoad)
        let building = try polygon("building", kind: .building, rings: [rectangle(20, 10, 80, 30)])
        let source = try MapDataset(features: [minor, major, building])
        for (columns, rows, span, minorVisible) in [(100, 40, 0.03, false), (100, 40, 0.01, true),
                                                   (200, 40, 0.02, true), (100, 40, 0.02, false),
                                                   (36, 18, 0.002, false), (100, 15, 0.002, false)] {
            let viewport = try MapViewport(columns: columns, rows: rows)
            let camera = try MapCamera(center: coordinate(0, 0), longitudeSpan: span)
            let prepared = try MapPreparation.prepare(dataset: source, camera: camera, viewport: viewport, detail: .abstract)
            #expect(prepared.lines.contains { $0.featureID == "minor" } == minorVisible)
            #expect(prepared.lines.contains { $0.featureID == "major" })
            #expect(!prepared.polygons.contains { $0.kind == .building })
            #expect(!prepared.labels.contains { $0.featureID == "building" })
        }
    }

    @Test("Abstract area admission uses visible filled area and holes rather than bounding boxes")
    func visibleAreaAdmission() throws {
        let source = try MapDataset(features: [
            polygon("large", kind: .park, rings: [rectangle(20, 10, 24, 14)]),
            polygon("small", kind: .park, rings: [rectangle(30, 10, 31, 11)]),
            polygon("mostly-hole", kind: .park, rings: [rectangle(40, 10, 44, 14), rectangle(40.1, 10.1, 43.9, 13.9)]),
            polygon("skinny", kind: .park, rings: [[.init(x: 10, y: 25), .init(x: 40, y: 35),
                                                   .init(x: 40, y: 34.8), .init(x: 10, y: 25)]]),
            polygon("mostly-offscreen", kind: .park, rings: [rectangle(-100, 10, 0.1, 14)]),
        ])
        let prepared = try prepare(source, detail: .abstract)
        #expect(prepared.polygons.map(\.featureID) == ["large"])
        #expect(prepared.lines.isEmpty) // Parks communicate area without competing outlines.
        #expect(prepared.labels.map(\.featureID) == ["large"])
        #expect(prepared.statistics.visibleFeatures == 1)
        #expect(try prepare(source, detail: .source).polygons.count == 5)
    }

    @Test("Visible-area admission adapts to allocation and cell aspect")
    func areaScale() throws {
        let source = try MapDataset(features: [polygon("park", kind: .park, rings: [rectangle(49, 19, 51, 21)])])
        let camera = try MapCamera(center: coordinate(0, 0), longitudeSpan: 100)
        #expect(try MapPreparation.prepare(dataset: source, camera: camera,
                                          viewport: MapViewport(columns: 100, rows: 40), detail: .abstract).polygons.isEmpty)
        #expect(try MapPreparation.prepare(dataset: source, camera: camera,
                                          viewport: MapViewport(columns: 200, rows: 40), detail: .abstract).polygons.count == 1)
        #expect(try MapPreparation.prepare(dataset: source, camera: camera,
                                          viewport: MapViewport(columns: 100, rows: 40, cellAspectRatio: 1),
                                          detail: .abstract).polygons.count == 1)
    }

    @Test("Admitted water retains exact source-mode rings and holes")
    func retainedHoles() throws {
        let source = try MapDataset(features: [polygon("water", kind: .water,
                                                       rings: [rectangle(-10, 10, 70, 30), rectangle(20, 15, 40, 25)])])
        let abstract = try prepare(source, detail: .abstract)
        let full = try prepare(source, detail: .source)
        #expect(abstract.polygons == full.polygons)
        #expect(abstract.polygons[0].rings.map(\.count) == [5, 5])
        #expect(abstract.lines == full.lines)
    }

    @Test("Major roads keep every visible path including short connecting geometry")
    func majorRoadContinuity() throws {
        let coordinates = try [coordinate(-60, 0), coordinate(-0.01, 0), coordinate(0, 0.01),
                               coordinate(0.01, 0), coordinate(60, 0)]
        let major = try MapFeature(id: "major", kind: .primaryRoad,
                                   geometry: .polyline(MapPolyline(coordinates: coordinates)))
        let short = try MapFeature(id: "connection", kind: .primaryRoad,
                                   geometry: .polyline(MapPolyline(coordinates: [coordinate(0.01, 0), coordinate(0.02, 0)])))
        let source = try MapDataset(features: [major, short])
        let abstract = try prepare(source, detail: .abstract)
        #expect(try abstract.lines == prepare(source, detail: .source).lines)
        #expect(Set(abstract.lines.map(\.featureID)) == ["major", "connection"])
        #expect(abstract.lines[0].points.first?.x == 0)
        #expect(abstract.lines[0].points.last?.x == 100)
    }

    @Test("Semantic admission is stable across feature order and identity or name changes")
    func stableAdmission() throws {
        let features = try [polygon("large", kind: .park, rings: [rectangle(20, 10, 24, 14)]),
                            polygon("small", kind: .park, rings: [rectangle(30, 10, 31, 11)]),
                            road("major", kind: .primaryRoad), road("minor", kind: .road)]
        let first = try prepare(MapDataset(features: features), detail: .abstract)
        let reverse = try prepare(MapDataset(features: Array(features.reversed())), detail: .abstract)
        #expect(Set(first.lines) == Set(reverse.lines))
        #expect(Set(first.polygons) == Set(reverse.polygons))
        #expect(Set(first.labels) == Set(reverse.labels))
        let renamed = try features.enumerated().map { index, feature in
            try MapFeature(id: "replacement-\(index)", kind: feature.kind, name: "Different place",
                           geometry: feature.geometry)
        }
        let changed = try prepare(MapDataset(features: renamed), detail: .abstract)
        #expect(first.polygons.map(\.rings) == changed.polygons.map(\.rings))
        #expect(first.lines.map(\.points) == changed.lines.map(\.points))
        #expect(first.statistics == changed.statistics)
    }

    @Test("The detail comparison preserves source values and the default preparation contract")
    func sourcePurity() throws {
        let source = try MapDataset(features: [road("minor", kind: .road), road("major", kind: .primaryRoad),
                                               polygon("building", kind: .building, rings: [rectangle(20, 10, 24, 14)])])
        let captured = source
        let camera = try MapCamera(center: coordinate(0, 0), longitudeSpan: 100)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let before = try MapPreparation.prepare(dataset: source, camera: camera, viewport: viewport)
        _ = try MapPreparation.prepare(dataset: source, camera: camera, viewport: viewport, detail: .abstract)
        #expect(source == captured)
        #expect(try before == prepare(source, detail: .source))
        #expect(before.statistics.sourceVertices == source.vertexCount)
        #expect(before.polygons.contains { $0.kind == .building })
        #expect(before.lines.contains { $0.kind == .road })
    }

    @Test("Real neighborhood overviews shed clutter while retaining major roads and water")
    func fixtureDensity() throws {
        let fixtures = try MapFixtures.load()
        for (columns, rows) in [(100, 20), (60, 20), (36, 18)] {
            let viewport = try MapViewport(columns: columns, rows: rows)
            let source = try MapPreparation.prepare(dataset: fixtures.street, camera: MapFixtures.Scene.street.camera,
                                                    viewport: viewport, detail: .source)
            let abstract = try MapPreparation.prepare(dataset: fixtures.street, camera: MapFixtures.Scene.street.camera,
                                                      viewport: viewport, detail: .abstract)
            #expect(abstract.statistics.visibleFeatures * 2 < source.statistics.visibleFeatures)
            #expect(abstract.statistics.preparedVertices * 2 < source.statistics.preparedVertices)
            #expect(abstract.statistics.sourceVertices == source.statistics.sourceVertices)
            #expect(abstract.lines.filter { $0.kind == .primaryRoad } == source.lines.filter { $0.kind == .primaryRoad })
            #expect(!abstract.lines.contains { $0.kind == .road || $0.kind == .building })
            #expect(abstract.polygons.contains { $0.kind == .water })
            #expect(abstract.polygons.contains { $0.kind == .park })
            #expect(!abstract.polygons.contains { $0.kind == .building })
        }
    }

    private func prepare(_ source: MapDataset, detail: MapDetail) throws -> PreparedMap {
        try MapPreparation.prepare(dataset: source, camera: MapCamera(center: coordinate(0, 0), longitudeSpan: 100),
                                   viewport: MapViewport(columns: 100, rows: 40), detail: detail)
    }

    private func road(_ id: String, kind: MapFeature.Kind) throws -> MapFeature {
        try MapFeature(id: id, kind: kind, name: id,
                       geometry: .polyline(MapPolyline(coordinates: [coordinate(-0.1, 0), coordinate(0.1, 0)])))
    }

    private func polygon(_ id: String, kind: MapFeature.Kind, rings: [[PreparedMap.Point]]) throws -> MapFeature {
        let converted = try rings.map { points in
            try MapRing(coordinates: points.map {
                try coordinate($0.x - 50, MapViewport.latitude(mercatorY: (20 - $0.y) * 2))
            })
        }
        return try MapFeature(id: id, kind: kind, name: id, geometry: .polygon(MapPolygon(rings: converted)))
    }

    private func rectangle(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> [PreparedMap.Point] {
        [.init(x: left, y: top), .init(x: right, y: top), .init(x: right, y: bottom),
         .init(x: left, y: bottom), .init(x: left, y: top)]
    }

    private func coordinate(_ longitude: Double, _ latitude: Double) throws -> MapCoordinate {
        try MapCoordinate(latitude: latitude, longitude: longitude)
    }
}
