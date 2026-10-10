@testable import ChioMaps
@testable import Chio
import Foundation
import Testing

struct MapDetailTests {
    @Test("Every feature class keeps its detail admission, outline and simplification policy")
    func featurePolicies() throws {
        let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 100)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let kinds: [MapFeature.Kind] = [.land, .water, .park, .building, .road, .primaryRoad]
        let policies: [(detail: MapDetail, admitted: [Bool], outlined: [Bool], tolerances: [Double])] = [
            (.silhouette, [true, true, false, false, false, false], [true, true, false, true, true, true],
             [1.5, 1.5, 0, 0, 0, 0]),
            (.minimal, [true, true, false, false, false, true], [true, true, false, true, true, true],
             [0.75, 0.75, 0, 0, 0, 0]),
            (.abstract, [true, true, true, false, false, true], [true, true, false, true, true, true],
             [0, 0, 0, 0, 0, 0]),
            (.source, [true, true, true, true, true, true], [true, true, true, true, true, true],
             [0, 0, 0, 0, 0, 0]),
        ]
        for policy in policies {
            #expect(kinds.map { policy.detail.admits($0, camera: camera, viewport: viewport) } == policy.admitted)
            #expect(kinds.map { policy.detail.outlines($0) } == policy.outlined)
            #expect(kinds.map { policy.detail.shapeTolerance(for: $0) } == policy.tolerances)
        }
    }

    @Test("Area thresholds are inclusive and other classes retain their explicit admission")
    func areaPolicyBoundaries() {
        let boundaries: [(detail: MapDetail, kind: MapFeature.Kind, minimum: Double)] = [
            (.silhouette, .land, 2), (.silhouette, .water, 4),
            (.minimal, .land, 2), (.minimal, .water, 4),
            (.abstract, .land, 0.5), (.abstract, .water, 1), (.abstract, .park, 6),
        ]
        for boundary in boundaries {
            #expect(!boundary.detail.admitsArea(boundary.minimum.nextDown, kind: boundary.kind))
            #expect(boundary.detail.admitsArea(boundary.minimum, kind: boundary.kind))
        }
        let kinds: [MapFeature.Kind] = [.land, .water, .park, .building, .road, .primaryRoad]
        let largeAreaPolicies: [(detail: MapDetail, admitted: [Bool])] = [
            (.silhouette, [true, true, false, false, false, false]),
            (.minimal, [true, true, false, false, false, true]),
            (.abstract, [true, true, true, false, true, true]),
            (.source, [true, true, true, true, true, true]),
        ]
        for policy in largeAreaPolicies {
            #expect(kinds.map { policy.detail.admitsArea(100, kind: $0) } == policy.admitted)
        }
        #expect(kinds.allSatisfy { MapDetail.source.admitsArea(0, kind: $0) })
    }

    @Test("Abstract road admission requires readable ground scale and both allocation boundaries")
    func roadPolicyBoundaries() throws {
        let center = try MapCoordinate(latitude: 0, longitude: 0)
        for (columns, rows, span, isAdmitted) in [(58, 16, 0.00625, true), (58, 16, 0.00626, false),
                                                (57, 16, 0.001, false), (58, 15, 0.001, false)] {
            let camera = try MapCamera(center: center, longitudeSpan: span)
            let viewport = try MapViewport(columns: columns, rows: rows)
            #expect(MapDetail.abstract.admits(.road, camera: camera, viewport: viewport) == isAdmitted)
            #expect(MapDetail.abstract.admits(.primaryRoad, camera: camera, viewport: viewport))
        }
    }

    @Test("Detail levels are ordered, bounded in either direction and cyclic when advanced")
    func steps() throws {
        let levels: [MapDetail] = [.silhouette, .minimal, .abstract, .source]
        #expect(MapDetail.allCases == levels)
        #expect(levels.map(\.levelNumber) == [1, 2, 3, 4])
        #expect(levels.map(\.less) == [.silhouette, .silhouette, .minimal, .abstract])
        #expect(levels.map(\.more) == [.minimal, .abstract, .source, .source])
        #expect(levels.map(\.next) == [.minimal, .abstract, .source, .silhouette])
        for level in levels {
            #expect(try JSONDecoder().decode(MapDetail.self, from: JSONEncoder().encode(level)) == level)
            #expect(MapDetail(rawValue: level.rawValue) == level)
        }
    }

    @Test("Silhouette and minimal admit geography while only minimal retains major roads")
    func reducedLayers() throws {
        let features = try [polygon("land", kind: .land, rings: [rectangle(10, 10, 20, 20)]),
                            polygon("water", kind: .water, rings: [rectangle(30, 10, 40, 20)]),
                            polygon("park", kind: .park, rings: [rectangle(50, 10, 60, 20)]),
                            polygon("building", kind: .building, rings: [rectangle(70, 10, 80, 20)]),
                            road("major", kind: .primaryRoad), road("minor", kind: .road)]
        let dataset = try MapDataset(features: features)
        let silhouette = try prepare(dataset, detail: .silhouette)
        let minimal = try prepare(dataset, detail: .minimal)
        #expect(Set(silhouette.polygons.map(\.featureID)) == ["land", "water"])
        #expect(Set(minimal.polygons.map(\.featureID)) == ["land", "water"])
        #expect(Set(silhouette.lines.map(\.kind)) == [.land, .water])
        #expect(Set(minimal.lines.map(\.kind)) == [.land, .water, .primaryRoad])
        #expect(Set(silhouette.labels.map(\.featureID)) == ["land", "water"])
        #expect(Set(minimal.labels.map(\.featureID)) == ["land", "water", "major"])
    }

    @Test("Reduced geography admission measures visible fill after clipping and hole subtraction",
          arguments: [MapDetail.silhouette, .minimal])
    func reducedAreas(detail: MapDetail) throws {
        let dataset = try MapDataset(features: [
            polygon("land-large", kind: .land, rings: [rectangle(10, 10, 13, 11)]),
            polygon("land-small", kind: .land, rings: [rectangle(20, 10, 21, 11)]),
            polygon("water-large", kind: .water, rings: [rectangle(30, 10, 33, 12)]),
            polygon("water-small", kind: .water, rings: [rectangle(40, 10, 43, 11)]),
            polygon("water-hole", kind: .water,
                    rings: [rectangle(50, 10, 54, 14), rectangle(50.1, 10.1, 53.9, 13.9)]),
            polygon("water-offscreen", kind: .water, rings: [rectangle(-100, 20, 0.1, 24)]),
        ])
        let reduced = try prepare(dataset, detail: detail)
        #expect(Set(reduced.polygons.map(\.featureID)) == ["land-large", "water-large"])
        #expect(Set(reduced.labels.map(\.featureID)) == ["land-large", "water-large"])
        #expect(try prepare(dataset, detail: .source).polygons.count == 6)
        #expect(!detail.admitsArea(1.999, kind: .land))
        #expect(detail.admitsArea(2, kind: .land))
        #expect(!detail.admitsArea(3.999, kind: .water))
        #expect(detail.admitsArea(4, kind: .water))
    }

    @Test("Abstract maps omit buildings and admit minor roads only at useful scale and allocation")
    func scaleAndAllocation() throws {
        let minor = try road("minor", kind: .road)
        let major = try road("major", kind: .primaryRoad)
        let building = try polygon("building", kind: .building, rings: [rectangle(20, 10, 80, 30)])
        let source = try MapDataset(features: [minor, major, building])
        for (columns, rows, span, isMinorVisible) in [(100, 40, 0.03, false), (100, 40, 0.01, true),
                                                   (200, 40, 0.02, true), (100, 40, 0.02, false),
                                                   (36, 18, 0.002, false), (100, 15, 0.002, false)] {
            let viewport = try MapViewport(columns: columns, rows: rows)
            let camera = try MapCamera(center: coordinate(0, 0), longitudeSpan: span)
            let prepared = try MapPreparation.prepare(dataset: source, camera: camera, viewport: viewport, detail: .abstract)
            #expect(prepared.lines.contains { $0.featureID == "minor" } == isMinorVisible)
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
            polygon("skinny", kind: .park, rings: [[PreparedMap.Point(x: 10, y: 25), PreparedMap.Point(x: 40, y: 35),
                                                   PreparedMap.Point(x: 40, y: 34.8), PreparedMap.Point(x: 10, y: 25)]]),
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

    @Test("Admitted water retains exact source-mode rings and holes", arguments: MapDetail.allCases)
    func retainedHoles(detail: MapDetail) throws {
        let source = try MapDataset(features: [polygon("water", kind: .water,
                                                       rings: [rectangle(-10, 10, 70, 30), rectangle(20, 15, 40, 25)])])
        let abstract = try prepare(source, detail: detail)
        let full = try prepare(source, detail: .source)
        #expect(abstract.polygons == full.polygons)
        #expect(abstract.polygons[0].rings.map(\.count) == [5, 5])
        #expect(abstract.lines == full.lines)
    }

    @Test("Major roads keep every visible path including short connecting geometry",
          arguments: [MapDetail.minimal, .abstract, .source])
    func majorRoadContinuity(detail: MapDetail) throws {
        let coordinates = try [coordinate(-60, 0), coordinate(-0.01, 0), coordinate(0, 0.01),
                               coordinate(0.01, 0), coordinate(60, 0)]
        let major = try MapFeature(id: "major", kind: .primaryRoad,
                                   geometry: .polyline(MapPolyline(coordinates: coordinates)))
        let short = try MapFeature(id: "connection", kind: .primaryRoad,
                                   geometry: .polyline(MapPolyline(coordinates: [coordinate(0.01, 0), coordinate(0.02, 0)])))
        let source = try MapDataset(features: [major, short])
        let abstract = try prepare(source, detail: detail)
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
        for detail in MapDetail.allCases {
            _ = try MapPreparation.prepare(dataset: source, camera: camera, viewport: viewport, detail: detail)
        }
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

    @Test("Real fixture feature admission grows with detail while lower geography changes shape")
    func fixtureLevels() throws {
        let fixtures = try MapFixtures.load()
        for scene in MapFixtures.Scene.allCases {
            let dataset = fixtures.dataset(for: scene)
            let captured = dataset
            let camera = scene.camera
            for (columns, rows) in [(100, 20), (60, 20), (36, 18)] {
                let viewport = try MapViewport(columns: columns, rows: rows)
                let maps = try MapDetail.allCases.map {
                    try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport, detail: $0)
                }
                for (less, more) in zip(maps, maps.dropFirst()) {
                    #expect(Set(less.polygons.map(\.featureID)).isSubset(of: Set(more.polygons.map(\.featureID))))
                    let lessIDs = Set(less.polygons.map(\.featureID) + less.lines.map(\.featureID))
                    let moreIDs = Set(more.polygons.map(\.featureID) + more.lines.map(\.featureID))
                    #expect(lessIDs.isSubset(of: moreIDs))
                    #expect(less.statistics.visibleFeatures <= more.statistics.visibleFeatures)
                    #expect(less.statistics.sourceVertices == more.statistics.sourceVertices)
                }
                // Lower geometry can fall back independently at either tolerance;
                // vertex counts need not be monotonically nested across candidates.
                let retainedIDs = Set(maps[0].polygons.map(\.featureID))
                let sourceGeography = maps[3].polygons.filter { retainedIDs.contains($0.featureID) }
                #expect(maps[0].polygons.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }
                        < sourceGeography.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } })
                #expect(maps[2].polygons.allSatisfy { maps[3].polygons.contains($0) })
                #expect(maps[0].statistics.visibleFeatures > 0)
                #expect(maps[0].polygons.allSatisfy { $0.kind == .land || $0.kind == .water })
                #expect(maps[1].lines.filter { $0.kind == .primaryRoad }
                        == maps[3].lines.filter { $0.kind == .primaryRoad })
                if scene == .street {
                    #expect(maps[0].statistics.visibleFeatures < maps[1].statistics.visibleFeatures)
                    #expect(maps[1].statistics.visibleFeatures < maps[2].statistics.visibleFeatures)
                    #expect(maps[2].statistics.visibleFeatures < maps[3].statistics.visibleFeatures)
                }
            }
            #expect(dataset == captured)
            #expect(camera == scene.camera)
        }
    }

    @Test("Lower levels change filled bays and matching outlines while abstract and source stay exact",
          arguments: [MapFeature.Kind.land, .water])
    func shapeGeneralization(kind: MapFeature.Kind) throws {
        let bay: [PreparedMap.Point] = [PreparedMap.Point(x: 10, y: 10), PreparedMap.Point(x: 18, y: 10),
                                       PreparedMap.Point(x: 18, y: 10.5), PreparedMap.Point(x: 22, y: 10.5),
                                       PreparedMap.Point(x: 22, y: 10), PreparedMap.Point(x: 30, y: 10),
                                       PreparedMap.Point(x: 30, y: 30), PreparedMap.Point(x: 10, y: 30), PreparedMap.Point(x: 10, y: 10)]
        let dataset = try MapDataset(features: [polygon("bay", kind: kind, rings: [bay])])
        let captured = dataset
        let maps = try MapDetail.allCases.map { try prepare(dataset, detail: $0) }
        #expect(maps[0].polygons[0].rings[0].count == 7)
        #expect(maps[1].polygons[0].rings[0].count > 7)
        #expect(maps[0].polygons[0].rings != maps[3].polygons[0].rings)
        #expect(maps[2].polygons == maps[3].polygons)
        #expect(maps[2].lines == maps[3].lines)
        let outline = maps[0].lines[0].points
        let fill = maps[0].polygons[0].rings[0]
        #expect(outline.count == fill.count)
        // Clipping recomputes segment endpoints, so compare at sub-cell precision
        // rather than requiring identical floating-point evaluation order.
        for (linePoint, fillPoint) in zip(outline, fill) {
            #expect(abs(linePoint.x - fillPoint.x) < 1e-9)
            #expect(abs(linePoint.y - fillPoint.y) < 1e-9)
        }
        #expect(abs(maps[0].labels[0].position.x - 20) < 1e-9)
        #expect(abs(maps[0].labels[0].position.y - 50.0 / 3) < 1e-9)
        #expect(dataset == captured)
        #expect(MapDetail.silhouette.shapeTolerance(for: kind) == 1.5)
        #expect(MapDetail.minimal.shapeTolerance(for: kind) == 0.75)
        #expect(MapDetail.abstract.shapeTolerance(for: kind) == 0)
        #expect(MapDetail.source.shapeTolerance(for: kind) == 0)
        #expect(MapDetail.silhouette.shapeTolerance(for: .park) == 0)
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
        [PreparedMap.Point(x: left, y: top), PreparedMap.Point(x: right, y: top), PreparedMap.Point(x: right, y: bottom),
         PreparedMap.Point(x: left, y: bottom), PreparedMap.Point(x: left, y: top)]
    }

    private func coordinate(_ longitude: Double, _ latitude: Double) throws -> MapCoordinate {
        try MapCoordinate(latitude: latitude, longitude: longitude)
    }
}
