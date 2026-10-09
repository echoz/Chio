@testable import ChioMapSpike
import SwiftTUIRuntime
import Testing

@MainActor
struct MapBudgetInteractionTests {
    @Test("An overloaded drawing preserves native focus and camera and recovers through detail or fill changes")
    func overloadRecovery() async throws {
        let loaded = try MapFixtures.load()
        let ring = try MapRing(coordinates: [
            MapCoordinate(latitude: 1.280, longitude: 103.843),
            MapCoordinate(latitude: 1.280, longitude: 103.870),
            MapCoordinate(latitude: 1.298, longitude: 103.870),
            MapCoordinate(latitude: 1.298, longitude: 103.843),
            MapCoordinate(latitude: 1.280, longitude: 103.843),
        ])
        let buildings = try (0..<300).map {
            try MapFeature(id: "building-\($0)", kind: .building,
                           geometry: .polygon(MapPolygon(rings: [ring])))
        }
        let road = try MapFeature(id: "road", kind: .primaryRoad, name: "Main Road",
                                  geometry: .polyline(MapPolyline(coordinates: [
                                    MapCoordinate(latitude: 1.289, longitude: 103.840),
                                    MapCoordinate(latitude: 1.289, longitude: 103.872),
                                  ])))
        let source = try MapSource(dataset: MapDataset(features: buildings + [road]),
                                   metadata: loaded.streetSource.metadata, coverage: loaded.streetSource.coverage)
        let fixtures = MapFixtures(worldSource: loaded.worldSource, streetSource: source,
                                   openFreeMapSource: loaded.openFreeMapSource)
        let frames = Frames()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                          onFrame: { frames.latest = $0 })
        let app = MapSpikeApplication(fixtures: fixtures, scene: .street, appearance: .default)
        let session = try HostedSceneSession(for: app, sceneID: WindowIdentifier("Chio map rendering spike"), surface: surface)
        let run = Task { try await session.start() }
        do {
            let initial = try await frames.wait { frame in
                frame.text.contains("detail 2/4 minimal") && frame.hasGeography && frame.focusedIdentity != nil
            }
            session.send([.key(.character("]")), .key(.character("]"))])
            let overloaded = try await frames.wait(after: initial.sequence) {
                $0.text.contains("Too much map detail") && $0.text.contains("detail 4/4 source")
            }
            #expect(!overloaded.hasGeography)
            #expect(overloaded.focusedIdentity == initial.focusedIdentity)
            session.send([.key(.arrowRight), .key(.character("t"))])
            let moved = try await frames.wait(after: overloaded.sequence) {
                $0.text.contains("Center 1.289, 103.870") && $0.text.contains("source · light")
                    && $0.text.contains("Too much map detail")
            }
            session.send(.key(.character("f")))
            let recovered = try await frames.wait(after: moved.sequence) {
                !$0.text.contains("Too much map detail") && $0.hasGeography
            }
            #expect(recovered.text.contains("Center 1.289, 103.870"))
            #expect(recovered.text.contains("detail 4/4 source"))
            #expect(recovered.focusedIdentity == initial.focusedIdentity)
            session.send(.key(.character("f")))
            let filled = try await frames.wait(after: recovered.sequence) { $0.text.contains("Too much map detail") }
            session.send([.key(.character("[")), .key(.character("["))])
            let minimal = try await frames.wait(after: filled.sequence) {
                $0.text.contains("detail 2/4 minimal") && !$0.text.contains("Too much map detail") && $0.hasGeography
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await frames.wait(after: minimal.sequence) { $0.text.contains("More room for the map") }
            surface.updateSurfaceSize(.init(width: 100, height: 30))
            session.requestSurfaceRefresh()
            let expanded = try await frames.wait(after: compact.sequence) {
                $0.raster.size == CellSize(width: 100, height: 30) && $0.hasGeography
            }
            #expect(expanded.text.contains("Center 1.289, 103.870"))
            #expect(expanded.text.contains("detail 2/4 minimal"))
            #expect(expanded.focusedIdentity == initial.focusedIdentity)
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    /// One bounded observation of public host output; no application state access.
    @MainActor
    private final class Frames {
        var latest: SemanticHostFrame?

        func wait(after sequence: UInt64? = nil,
                  matching predicate: (SemanticHostFrame) -> Bool) async throws -> SemanticHostFrame {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while ContinuousClock.now < deadline {
                if let latest, sequence.map({ latest.sequence > $0 }) ?? true, predicate(latest) { return latest }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw Timeout(frame: latest.map {
                "Sequence \($0.sequence), focus \(String(describing: $0.focusedIdentity))\n\($0.text)"
            } ?? "No frame received")
        }

        private struct Timeout: Error, CustomStringConvertible {
            let frame: String
            var description: String { "Timed out waiting for map frame:\n\(frame)" }
        }
    }
}

private extension SemanticHostFrame {
    var text: String { raster.lines.joined(separator: "\n") }
    var hasGeography: Bool { text.unicodeScalars.contains { (0x2801...0x28FF).contains($0.value) } }
}
