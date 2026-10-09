@testable import Chio
import Foundation
import Synchronization
import Testing

struct MapPreparationCancellationTests {
    @Test("Cancellation rejects preparation before work and during a long projected path")
    func cancelledPreparation() throws {
        let coordinates = try (0...4_096).map {
            try MapCoordinate(latitude: 0, longitude: -5 + Double($0) / 4_096 * 10)
        }
        let dataset = try MapDataset(features: [
            MapFeature(id: "road", kind: .road, name: "Road",
                       geometry: .polyline(MapPolyline(coordinates: coordinates))),
        ])
        let captured = dataset
        let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 20)
        let viewport = try MapViewport(columns: 100, rows: 40)
        for stopAt in [1, 10] {
            let probe = Probe(stopAt: stopAt)
            #expect(throws: CancellationError.self) {
                try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport,
                                           isCancelled: { probe.observe() })
            }
            #expect(probe.count == stopAt)
            #expect(dataset == captured)
        }
        let expected = try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport)
        #expect(try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport,
                                           isCancelled: { false }) == expected)
        #expect(expected.statistics.visibleFeatures == 1)
    }

    @Test("Cancelled generalization returns the whole input and retains consumed work accounting")
    func cancelledShapeReduction() {
        let rings = [circle(samples: 1_024)]
        let captured = rings
        var initialBudget = MapShapeSimplification.operationLimit
        let initialProbe = Probe(stopAt: 1)
        #expect(MapShapeSimplification.simplify(rings, tolerance: 0.2, cellAspectRatio: 1,
                                               operationBudget: &initialBudget,
                                               isCancelled: { initialProbe.observe() }) == rings)
        #expect(initialBudget == MapShapeSimplification.operationLimit)

        let completedProbe = Probe()
        var completedBudget = MapShapeSimplification.operationLimit
        let completed = MapShapeSimplification.simplify(rings, tolerance: 0.2, cellAspectRatio: 1,
                                                        operationBudget: &completedBudget,
                                                        isCancelled: { completedProbe.observe() })
        #expect(completed[0].count < rings[0].count)
        #expect(completedProbe.count > 10)
        // A probe just before completion reaches the quadratic topology checks,
        // rather than merely testing cancellation at the entry boundary.
        let lateProbe = Probe(stopAt: completedProbe.count - 1)
        var cancelledBudget = MapShapeSimplification.operationLimit
        #expect(MapShapeSimplification.simplify(rings, tolerance: 0.2, cellAspectRatio: 1,
                                               operationBudget: &cancelledBudget,
                                               isCancelled: { lateProbe.observe() }) == rings)
        #expect(MapShapeSimplification.operationLimit - cancelledBudget > 100_000)
        #expect(cancelledBudget >= completedBudget)
        #expect(rings == captured)

        var defaultBudget = MapShapeSimplification.operationLimit
        #expect(MapShapeSimplification.simplify(rings, tolerance: 0.2, cellAspectRatio: 1,
                                               operationBudget: &defaultBudget) == completed)
        #expect(defaultBudget == completedBudget)
    }

    @Test("Preparation rejects a cancelled shape fallback instead of publishing source geometry")
    func cancelledPolygonPreparation() throws {
        let ring = try MapRing(coordinates: circle(samples: 1_024).map {
            try MapCoordinate(latitude: $0.y / 100, longitude: $0.x / 100)
        })
        let dataset = try MapDataset(features: [
            MapFeature(id: "land", kind: .land, geometry: .polygon(MapPolygon(rings: [ring]))),
        ])
        let captured = dataset
        let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 4)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let expected = try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport,
                                                   detail: .minimal)
        #expect(!expected.polygons.isEmpty)
        let lateProbe = Probe(stopAt: 100)
        #expect(throws: CancellationError.self) {
            try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport,
                                       detail: .minimal, isCancelled: { lateProbe.observe() })
        }
        // The simplifier observes cancellation and returns its original rings;
        // preparation's immediately following observation then rejects them.
        #expect(lateProbe.count == 101)
        #expect(dataset == captured)
    }

    private func circle(samples: Int) -> [PreparedMap.Point] {
        let points = (0..<samples).map { index in
            let angle = Double(index) / Double(samples) * 2 * .pi
            return PreparedMap.Point(x: cos(angle) * 100, y: sin(angle) * 100)
        }
        return points + [points[0]]
    }

    /// A deterministic observation counter; no task scheduler or clock is involved.
    private final class Probe: Sendable {
        let stopAt: Int?
        private let observations = Mutex(0)

        init(stopAt: Int? = nil) { self.stopAt = stopAt }

        var count: Int { observations.withLock { $0 } }

        func observe() -> Bool {
            observations.withLock { count in
                count += 1
                return stopAt.map { count >= $0 } ?? false
            }
        }
    }
}
