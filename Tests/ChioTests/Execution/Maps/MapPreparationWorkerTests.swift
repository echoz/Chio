@testable import Chio
import Dispatch
import Foundation
import Synchronization
import Testing

struct MapPreparationWorkerTests {
    @Test("One worker rejects cancelled active and queued requests and accepts the latest request")
    func cancellationAndSerialization() async throws {
        let control = Control()
        let worker = MapPreparationWorker(operation: { try control.prepare($0) })
        let firstRequest = try request(span: 10)
        let staleRequest = try request(span: 20)
        let latestRequest = try request(span: 30)
        let firstFinished = Latch()
        let first = Task {
            defer { firstFinished.signal() }
            return try await worker.prepare(firstRequest)
        }
        defer { first.cancel(); control.releaseFirst.signal() }
        try await control.firstEntered.wait()

        let staleStarted = Latch(), staleFinished = Latch()
        let stale = Task {
            defer { staleFinished.signal() }
            staleStarted.signal()
            return try await worker.prepare(staleRequest)
        }
        defer { stale.cancel() }
        try await staleStarted.wait()
        let latestStarted = Latch(), latestFinished = Latch()
        let latest = Task {
            defer { latestFinished.signal() }
            latestStarted.signal()
            return try await worker.prepare(latestRequest)
        }
        defer { latest.cancel() }
        try await latestStarted.wait()
        // The first synchronous operation still owns the actor's executor.
        // Neither later request can have entered the injected operation.
        #expect(control.calls == [10])
        first.cancel()
        stale.cancel()
        control.releaseFirst.signal()

        try await firstFinished.wait()
        try await staleFinished.wait()
        try await latestFinished.wait()
        expectCancellation(await first.result)
        expectCancellation(await stale.result)
        let accepted = try await latest.value
        #expect(accepted.viewport == latestRequest.viewport)
        #expect(control.calls == [10, 30])
        #expect(control.maximumActive == 1)

        // Cancellation must not poison the retained serial owner.
        let recovered = try await worker.prepare(request(span: 40))
        #expect(recovered.viewport == latestRequest.viewport)
        #expect(control.calls == [10, 30, 40])
        #expect(control.maximumActive == 1)
    }

    @Test("The real worker preserves route clipping across the dateline at every detail level")
    func routesAcrossDetailLevels() async throws {
        let path = try MapPolyline(coordinates: [
            MapCoordinate(latitude: 0, longitude: 178),
            MapCoordinate(latitude: 0, longitude: -178),
        ])
        let dataset = try MapDataset(features: [
            MapFeature(id: "minor-road", kind: .road, geometry: .polyline(path)),
        ])
        let route = try MapRoute(id: "route", path: path)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let localCamera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 179), longitudeSpan: 20)
        let worldCamera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 360)
        let worker = MapPreparationWorker()
        var firstRoutes: [PreparedMap.Line]?
        for detail in MapDetail.allCases {
            let local = try await worker.prepare(.init(dataset: dataset, camera: localCamera, viewport: viewport,
                                                       detail: detail, routes: [route], fills: false))
            #expect(local.routes.count == 1)
            #expect(local.routes[0].featureID == "route")
            #expect(local.routes[0].points == [.init(x: 45, y: 20), .init(x: 65, y: 20)])
            if let firstRoutes { #expect(local.routes == firstRoutes) } else { firstRoutes = local.routes }
            if detail == .silhouette { #expect(local.map.lines.isEmpty) }
            let world = try await worker.prepare(.init(dataset: dataset, camera: worldCamera, viewport: viewport,
                                                       detail: detail, routes: [route], fills: false))
            #expect(world.routes.count == 2)
            #expect(world.routes.contains { $0.points.first?.x == 0 })
            #expect(world.routes.contains { $0.points.last?.x == 100 })
            #expect(world.routes.allSatisfy { abs($0.points.last!.x - $0.points.first!.x) < 1 })
        }
    }

    @Test("Named routes retain their clipped midpoint labels independently of geographic names")
    func routeTitles() async throws {
        let path = try MapPolyline(coordinates: [
            MapCoordinate(latitude: 0, longitude: -50),
            MapCoordinate(latitude: 0, longitude: 50),
        ])
        // Overlay IDs have their own namespace, even when source geometry uses
        // the same ID and carries a different application-independent name.
        let dataset = try MapDataset(features: [
            MapFeature(id: "shared", kind: .primaryRoad, name: "Street", geometry: .polyline(path)),
        ])
        let named = try MapRoute(id: "shared", title: "Walk", path: path)
        let unnamed = try MapRoute(id: "unnamed", path: path)
        let viewport = try MapViewport(columns: 100, rows: 40)
        let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 20)
        let worker = MapPreparationWorker()
        let baseline = try await worker.prepare(.init(dataset: dataset, camera: camera, viewport: viewport,
                                                       detail: .source, routes: [], fills: false))
        let drawing = try await worker.prepare(.init(dataset: dataset, camera: camera, viewport: viewport,
                                                      detail: .source, routes: [named, unnamed], fills: false))
        #expect(drawing.map == baseline.map)
        #expect(drawing.map.labels.map(\.text) == ["Street"])
        #expect(drawing.routes.count == 2)
        #expect(drawing.routeLabels == [
            .init(featureID: "shared", kind: .primaryRoad, text: "Walk", position: .init(x: 50, y: 20)),
        ])
        #expect(baseline.routeLabels.isEmpty)
    }

    private func request(span: Double) throws -> MapPreparationRequest {
        try .init(dataset: MapDataset(features: []),
                  camera: MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: span),
                  viewport: MapViewport(columns: 100, rows: 40), detail: .minimal, routes: [], fills: true)
    }

    private func expectCancellation(_ result: Result<PreparedMapDrawing, any Error>) {
        switch result {
        case .failure(let error): #expect(error is CancellationError)
        case .success: Issue.record("Cancelled preparation returned a drawing")
        }
    }

    /// Only this test effect owner blocks; every wait has a five-second bound.
    private final class Control: Sendable {
        let firstEntered = Latch()
        let releaseFirst = Latch()
        private let observations = Mutex(Observation())

        var calls: [Double] { observations.withLock { $0.calls } }
        var maximumActive: Int { observations.withLock { $0.maximumActive } }

        func prepare(_ request: MapPreparationRequest) throws -> PreparedMapDrawing {
            observations.withLock {
                $0.calls.append(request.camera.longitudeSpan)
                $0.active += 1
                $0.maximumActive = max($0.maximumActive, $0.active)
            }
            defer { observations.withLock { $0.active -= 1 } }
            if request.camera.longitudeSpan == 10 {
                firstEntered.signal()
                try releaseFirst.waitSynchronously()
            }
            let map = PreparedMap(lines: [], polygons: [], labels: [],
                                  statistics: .init(sourceVertices: 0, preparedVertices: 0, visibleFeatures: 0))
            return try PreparedMapDrawing(map: map, routes: [], viewport: request.viewport, fills: request.fills)
        }

        private struct Observation {
            var calls: [Double] = []
            var active = 0
            var maximumActive = 0
        }
    }

    private final class Latch: Sendable {
        private let semaphore = DispatchSemaphore(value: 0)

        func signal() { semaphore.signal() }

        func waitSynchronously() throws {
            guard semaphore.wait(timeout: .now() + 5) == .success else { throw WaitError.timeout }
        }

        func wait() async throws {
            let succeeded = await withCheckedContinuation { continuation in
                DispatchQueue.global().async { [self] in
                    continuation.resume(returning: semaphore.wait(timeout: .now() + 5) == .success)
                }
            }
            guard succeeded else { throw WaitError.timeout }
        }
    }

    private enum WaitError: Error { case timeout }
}
