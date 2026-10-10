@testable import Chio
@testable import ChioMaps
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct MapPackExampleTests {
    @Test("Pack launch and preparation are explicit and reject network and bundled-output combinations")
    func commandLine() throws {
        let viewing = try MapExampleCommand.parse(["--tile-pack", "/tmp/world-pack", "--map", "street"])
        #expect(viewing.tilePack == "/tmp/world-pack")
        #expect(!viewing.online && viewing.scene == .street)
        let writing = try MapExampleCommand.parse(["--write-tile-pack", "/tmp/world-pack"])
        #expect(writing.writeTilePack == "/tmp/world-pack")
        let bundled = try MapExampleCommand.parse([])
        #expect(bundled.tilePack.isEmpty && bundled.writeTilePack.isEmpty && !bundled.online)
        for option in ["--tile-pack", "--write-tile-pack"] {
            for incompatible in [["--online"], ["--tile-cache", "/tmp/cache"], ["--tile-source", "source.json"],
                                 ["--source", "openfreemap"], ["--snapshot"], ["--snapshot-json"], ["--benchmark"]] {
                #expect(throws: (any Error).self) {
                    try MapExampleCommand.parse([option, "/tmp/pack"] + incompatible)
                }
            }
        }
        #expect(throws: (any Error).self) {
            try MapExampleCommand.parse(["--tile-pack", "/tmp/pack", "--write-tile-pack", "/tmp/other"])
        }
    }

    @Test("Bundled pack preparation closes ownership and reopened tiles retain complete world geometry")
    func prepareAndLoad() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chio-example-pack-\(UUID().uuidString).chiomap")
        defer { try? FileManager.default.removeItem(at: file) }
        try await MapExamplePack.writeWorld(at: file)
        let pack = try MapTilePack.open(at: file)
        do {
            let acquisition = MapExampleAcquisition.pack(MapTileLoader(pack: pack))
            #expect(acquisition.usesTiles && !acquisition.isOnline)
            #expect(acquisition.title == "Offline pack")
            let loader = try await acquisition.makeLoader()
            let viewport = try MapViewport(columns: 98, rows: 48)
            for longitude in [0.0, 179.0, -179.0] {
                let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: longitude), longitudeSpan: 360)
                let request = MapTileRequest(camera: camera, viewport: viewport)
                let snapshot = try await loader.load(request)
                #expect(snapshot.request == request && snapshot.attainedZoom == 1)
                #expect(snapshot.source.dataset.features.count == 30)
                #expect(snapshot.source.dataset.vertexCount == 5_190)
                #expect(snapshot.source.metadata.attribution.contains("fixture replay"))
                guard case .tiled(let coverage) = snapshot.source.coverage else {
                    Issue.record("Expected complete world tile coverage")
                    continue
                }
                #expect(coverage.covers(request))
                #expect(Set(coverage.tiles) == Set(try [
                    MapTileCoordinate(zoom: 1, x: 0, y: 0), MapTileCoordinate(zoom: 1, x: 0, y: 1),
                    MapTileCoordinate(zoom: 1, x: 1, y: 0), MapTileCoordinate(zoom: 1, x: 1, y: 1)
                ]))
            }
        } catch {
            await pack.close()
            throw error
        }
        await pack.close()
    }

    @Test("Unavailable pack coverage retains native focus, accepted source, camera, theme and detail")
    func unavailableCoverage() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chio-partial-pack-\(UUID().uuidString).chiomap")
        defer { try? FileManager.default.removeItem(at: file) }
        let bounds = try MapCoverage.Bounds(
            southwest: MapCoordinate(latitude: 30, longitude: -120),
            northeast: MapCoordinate(latitude: 60, longitude: -60))
        let plan = try MapTilePackPlan(bounds: bounds, zoomRange: 1...1)
        let metadata = try MapFixtures.load().openFreeMapSource.metadata
        // Empty protobuf is a valid tile; this scenario exercises resource coverage,
        // state and provenance rather than geographic raster quality.
        let pack = try await MapTilePack.create(at: file, plan: plan, metadata: metadata) { _ in Data() }
        let loader = MapTileLoader(pack: pack)
        let frames = PackFrames()
        let surface = HostedRasterSurface(surfaceSize: CellSize(width: 100, height: 32), appearance: .fallback,
                                          onFrame: { frames.latest = $0 })
        let session: HostedSceneSession
        do {
            session = try HostedSceneSession(for: PackTestApp(loader: loader), sceneID: "pack-example-tests", surface: surface)
        } catch {
            await pack.close()
            throw error
        }
        let run = Task { try await session.start() }
        do {
            let accepted = try await frames.wait { $0.packText.contains("Offline pack · z1") }
            let focus = try #require(accepted.focusedIdentity)
            session.send([.key(.character("w"), modifiers: .ctrl), .key(.character("d"), modifiers: .ctrl),
                          .key(.character("t"), modifiers: .ctrl)])
            let unavailable = try await frames.wait {
                $0.packText.contains("Offline pack · area unavailable")
                    && $0.packText.contains("Detail=source Theme=light")
                    && $0.packText.contains("Span=360.0000")
            }
            #expect(unavailable.focusedIdentity == focus)
            #expect(unavailable.packText.contains("showing previous coverage"))
            #expect(unavailable.packText.contains(metadata.attribution))
            session.send([.key(.character("e"), modifiers: .ctrl)])
            try await Task.sleep(for: .milliseconds(350))
            #expect(frames.latest?.packText.contains("Offline pack · area unavailable") == true)
            #expect(frames.latest?.focusedIdentity == focus)
            session.send([.key(.arrowRight)])
            let moved = try await frames.wait { $0.packText.contains("Lon=43.200 Span=360.0000") }
            #expect(moved.focusedIdentity == focus)
            #expect(moved.packText.contains("Detail=source Theme=light"))
            session.send([.key(.character("w"), modifiers: .ctrl)])
            let recovered = try await frames.wait {
                $0.packText.contains("Offline pack · z1") && $0.packText.contains("Lon=-90.000 Span=30.0000")
            }
            #expect(recovered.focusedIdentity == focus)
            #expect(recovered.packText.contains("Detail=source Theme=light"))
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            await pack.close()
            throw error
        }
        await pack.close()
    }

}

private struct PackTestApp {
    let loader: MapTileLoader?
    nonisolated init() { loader = nil }
    nonisolated init(loader: MapTileLoader) { self.loader = loader }
}

extension PackTestApp: App {
    var body: some Scene {
        WindowGroup(id: "pack-example-tests") {
            if let loader { PackTestView(loader: loader) }
        }.exitOnKeys([])
    }
}

@MainActor
private struct PackTestView {
    let loader: MapTileLoader
    @State private var camera = try! MapCamera(center: MapCoordinate(latitude: 45, longitude: -90), longitudeSpan: 30)
    @State private var selection: String?
    @State private var detail = MapDetail.minimal
    @State private var light = false
    @State private var retry = 0
}

extension PackTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TiledMapContent(camera: $camera, selection: $selection, overlays: .empty, detail: detail,
                            fillsAreas: true, showsLabels: true, retry: retry, sourceLabel: "Offline pack",
                            activate: { _ in }, makeLoader: { loader })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(String(format: "Lon=%.3f Span=%.4f", camera.center.longitude, camera.longitudeSpan))
                .frame(height: 1, alignment: .leading)
            Text("Detail=\(detail.rawValue) Theme=\(light ? "light" : "default")")
                .frame(height: 1, alignment: .leading)
        }
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("w"):
                if camera.longitudeSpan == 360 {
                    camera = try! MapCamera(center: MapCoordinate(latitude: 45, longitude: -90), longitudeSpan: 30)
                } else { camera = MapFixtures.Scene.world.camera }
            case .character("d"): detail = .source
            case .character("t"): light.toggle()
            case .character("e"): retry += 1
            default: return .ignored
            }
            return .handled
        }
        .chioTheme(light ? .light : .default)
    }
}

@MainActor
private final class PackFrames {
    var latest: SemanticHostFrame?

    func wait(matching predicate: (SemanticHostFrame) -> Bool) async throws -> SemanticHostFrame {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let latest, predicate(latest) { return latest }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FrameTimeout(text: latest?.packText ?? "No frame received")
    }

    private struct FrameTimeout: Error, CustomStringConvertible {
        let text: String
        var description: String { "Timed out waiting for pack frame:\n\(text)" }
    }
}

private extension SemanticHostFrame {
    var packText: String { raster.lines.joined(separator: "\n") }
}
