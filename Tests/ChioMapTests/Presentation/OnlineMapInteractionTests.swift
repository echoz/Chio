@testable import ChioMaps
@testable import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct OnlineMapInteractionTests {
    @Test("Explicit online launch accepts interactive use and rejects offline output or ambiguous source flags")
    func commandLine() throws {
        #expect(try !MapExampleCommand.parse([]).online)
        let online = try MapExampleCommand.parse(["--online", "--map", "street", "--detail", "source"])
        #expect(online.online && online.scene == .street && online.detail == .source)
        for flags in [["--online", "--snapshot"], ["--online", "--snapshot-json"],
                      ["--online", "--benchmark"], ["--online", "--source", "openfreemap"],
                      ["--tile-source", "source.json"]] {
            #expect(throws: (any Error).self) { try MapExampleCommand.parse(flags) }
        }
    }

    @Test("Explicit online source files decode a bounded checked configuration without provider discovery")
    func configuredSourceFile() throws {
        let url = URL(string: "https://example.test")!
        let source = try OpenMapTilesSource(template: "https://example.test/{z}/{x}/{y}.pbf", zoomRange: 1...14,
            metadata: MapSourceMetadata(attribution: "Configured provider", license: "Fixture license",
                                        licenseURL: url, sourceURL: url, sourceRevision: "configured-test"))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chio-online-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode(source).write(to: file)
        let command = try MapExampleCommand.parse(["--online", "--tile-source", file.path])
        #expect(command.online && command.tileSource == file.path)
        #expect(try MapExampleAcquisition.configured(file: command.tileSource) == .configured(source))
        try Data("{}".utf8).write(to: file)
        #expect(throws: (any Error).self) { try MapExampleAcquisition.configured(file: file.path) }
        try Data(repeating: 0x61, count: 16 * 1_024 + 1).write(to: file)
        #expect(throws: MapValidationError.invalidTileSource) { try MapExampleAcquisition.configured(file: file.path) }
    }

    @Test("Online loading, whole-viewport pan, failure and explicit retry retain the same native focus")
    func loadingPanFailureRetry() async throws {
        try await withOnlineScene(held: true) { session, _, frames, transport in
            let loading = try await frames.wait {
                $0.onlineText.contains("Loading tiles") && $0.onlineText.contains("no map loaded")
                    && $0.focusedIdentity != nil
            }
            #expect(loading.onlineText.contains("No map source loaded"))
            let loadingHasGeography = loading.onlineHasGeography
            #expect(!loadingHasGeography)
            #expect(!loading.onlineText.contains("Natural Earth"))
            #expect(!loading.onlineText.contains("Controlled tiles"))
            #expect(!loading.onlineText.contains("Fixture license"))
            try await transport.waitForRequests(2)
            await transport.release()
            let initial = try await frames.wait(after: loading.sequence) { $0.onlineReady }
            #expect(initial.focusedIdentity == loading.focusedIdentity)
            #expect(await transport.paths() == initialPaths)
            #expect(await transport.factoryCalls == 1)

            let initialCount = await transport.count
            session.send([.key(.character("d"), modifiers: .ctrl), .key(.character("t"), modifiers: .ctrl),
                          .key(.character("b"), modifiers: .ctrl)])
            let restyled = try await frames.wait(after: initial.sequence) {
                $0.onlineReady && $0.onlineText.contains("Detail=source Theme=light B=1")
                    && !$0.onlineText.contains("Preparing map")
            }
            // Bound this negative observation beyond the example's 150 ms coalescing interval.
            try await Task.sleep(for: .milliseconds(350))
            #expect(await transport.count == initialCount)
            #expect(restyled.focusedIdentity == initial.focusedIdentity)

            session.send(Array(repeating: .key(.arrowRight), count: 6))
            let moved = try await frames.wait(after: restyled.sequence) {
                $0.onlineReady && $0.onlineText.contains("Lon=103.888")
            }
            #expect(moved.focusedIdentity == initial.focusedIdentity)
            // Native input/rendering may span the 150 ms coalescing interval.
            // Earlier cameras may therefore start valid, superseded loads. The
            // no-store fixture and drained replacements make the final four
            // requests belong to the completed final viewport, with no new input.
            let panPaths = await transport.orderedPaths(after: initialCount)
            let finalPaths = Set(panPaths.suffix(movedPaths.count))
            #expect(finalPaths == movedPaths, "Pan requests: \(panPaths)")
            #expect(Set(panPaths).isSubset(of: initialPaths.union(movedPaths)),
                    "Unexpected intermediate pan requests: \(panPaths)")

            await transport.setFailure(true)
            session.send(.key(.arrowRight))
            let failed = try await frames.wait(after: moved.sequence) {
                $0.onlineText.contains("Could not load this area")
                    && $0.onlineText.contains("showing previous coverage")
                    && $0.onlineText.contains("Controlled tiles") && $0.onlineText.contains("Lon=103.891")
            }
            #expect(failed.focusedIdentity == initial.focusedIdentity)
            let failedCount = await transport.count
            await transport.setFailure(false)
            session.send(.key(.character("e"), modifiers: .ctrl))
            let retried = try await frames.wait(after: failed.sequence) {
                $0.onlineReady && $0.onlineText.contains("Lon=103.891")
            }
            #expect(await transport.count > failedCount)
            #expect(retried.focusedIdentity == initial.focusedIdentity)
        }
    }

    @Test("Initial online failure keeps geography absent and interactive bindings recover on explicit retry")
    func initialFailureRetry() async throws {
        try await withOnlineScene(fails: true, markers: true) { session, _, frames, transport in
            let failed = try await frames.wait {
                $0.onlineText.contains("Could not load this area") && $0.onlineText.contains("no map loaded")
                    && $0.focusedIdentity != nil
            }
            #expect(failed.onlineText.contains("No map source loaded"))
            let failedHasGeography = failed.onlineHasGeography
            #expect(!failedHasGeography)
            #expect(!failed.onlineText.contains("Natural Earth"))
            #expect(!failed.onlineText.contains("Controlled tiles"))
            #expect(!failed.onlineText.contains("Fixture license"))
            #expect(await transport.paths().isSubset(of: initialPaths))

            session.send([.key(.character("n")), .key(.return), .key(.character("+")), .key(.arrowRight),
                          .key(.character("b"), modifiers: .ctrl)])
            let controlled = try await frames.wait(after: failed.sequence) {
                $0.onlineText.contains("Could not load this area") && $0.onlineText.contains("Lon=103.869 Span=0.0210")
                    && $0.onlineText.contains("B=1 S=place A=place")
            }
            #expect(controlled.onlineText.contains("No map source loaded"))
            let controlledHasGeography = controlled.onlineHasGeography
            #expect(!controlledHasGeography)
            #expect(controlled.focusedIdentity == failed.focusedIdentity)
            let beforeRetry = await transport.count
            await transport.setFailure(false)
            session.send(.key(.character("e"), modifiers: .ctrl))
            let recovered = try await frames.wait(after: controlled.sequence) {
                $0.onlineReady && $0.onlineText.contains("Controlled tiles")
                    && $0.onlineText.contains("Lon=103.869 Span=0.0210")
                    && $0.onlineText.contains("B=1 S=place A=place")
            }
            #expect(!recovered.onlineText.contains("No map source loaded"))
            #expect(!recovered.onlineText.contains("Natural Earth"))
            // The narrower 0.021° camera intersects only the southern z14 row.
            #expect(await transport.count == beforeRetry + 2)
            #expect(await transport.paths(after: beforeRetry) == ["/14/12918/8133.pbf", "/14/12919/8133.pbf"])
            #expect(await transport.factoryCalls == 1)
            #expect(recovered.focusedIdentity == failed.focusedIdentity)
        }
    }

    @Test("World and street cameras acquire online tiles with one loader while compact allocations pause I/O")
    func allocationAndWorld() async throws {
        try await withOnlineScene(startsWorld: true) { session, surface, frames, transport in
            let world = try await frames.wait {
                $0.onlineText.contains("Online · z1") && $0.focusedIdentity != nil
            }
            #expect(await transport.paths() == worldPaths)
            #expect(await transport.count == 4)
            #expect(await transport.factoryCalls == 1)
            #expect(world.onlineText.contains("Controlled tiles"))
            #expect(!world.onlineText.contains("Natural Earth"))
            session.send(.key(.character("w"), modifiers: .ctrl))
            let street = try await frames.wait(after: world.sequence) { $0.onlineReady }
            #expect(street.focusedIdentity == world.focusedIdentity)
            #expect(await transport.count == 8)
            #expect(await transport.paths(after: 4) == initialPaths)
            let beforeCompact = await transport.count
            surface.updateSurfaceSize(CellSize(width: 40, height: 14))
            session.requestSurfaceRefresh()
            let compact = try await frames.wait(after: street.sequence) {
                $0.onlineText.contains("Online paused") && $0.onlineText.contains("More room for the map")
            }
            #expect(compact.focusedIdentity == street.focusedIdentity)
            session.send([.key(.arrowRight), .key(.character("b"), modifiers: .ctrl)])
            let changed = try await frames.wait(after: compact.sequence) {
                $0.onlineText.contains("Lon=103.870") && $0.onlineText.contains("B=1")
            }
            try await Task.sleep(for: .milliseconds(350))
            #expect(await transport.count == beforeCompact)
            surface.updateSurfaceSize(CellSize(width: 100, height: 32))
            session.requestSurfaceRefresh()
            let expanded = try await frames.wait(after: changed.sequence) {
                $0.onlineReady && $0.onlineText.contains("Lon=103.870")
            }
            #expect(await transport.count == beforeCompact + 4)
            #expect(expanded.focusedIdentity == street.focusedIdentity)
            session.send(.key(.character("w"), modifiers: .ctrl))
            let backToWorld = try await frames.wait(after: expanded.sequence) { $0.onlineText.contains("Online · z1") }
            let worldCount = await transport.count
            #expect(worldCount == beforeCompact + 8)
            #expect(await transport.paths(after: worldCount - 4) == worldPaths)
            #expect(backToWorld.focusedIdentity == street.focusedIdentity)
            session.send(.key(.character("w"), modifiers: .ctrl))
            let resumed = try await frames.wait(after: backToWorld.sequence) { $0.onlineReady }
            #expect(await transport.count == worldCount + 4)
            #expect(await transport.factoryCalls == 1)
            #expect(resumed.focusedIdentity == street.focusedIdentity)
        }
    }

    @Test("An uncancellable old transport completion cannot publish over a newer camera request")
    func staleCompletion() async throws {
        try await withOnlineScene(held: true) { session, _, frames, transport in
            let initial = try await frames.wait { $0.onlineText.contains("Loading tiles") && $0.focusedIdentity != nil }
            try await transport.waitForRequests(2)
            session.send(Array(repeating: .key(.arrowRight), count: 6))
            let moved = try await frames.wait(after: initial.sequence) {
                $0.onlineText.contains("Lon=103.888") && $0.onlineText.contains("Loading tiles")
            }
            try await Task.sleep(for: .milliseconds(200))
            // Finish the old transport despite cancellation; keep the successor held.
            await transport.release(keepingHeld: true)
            try await transport.waitForRequests(4)
            session.send(.key(.character("b"), modifiers: .ctrl))
            let pendingNew = try await frames.wait(after: moved.sequence) { $0.onlineText.contains("B=1") }
            #expect(pendingNew.onlineText.contains("Loading tiles"))
            #expect(pendingNew.onlineText.contains("no map loaded"))
            #expect(pendingNew.onlineText.contains("No map source loaded"))
            let pendingNewHasGeography = pendingNew.onlineHasGeography
            #expect(!pendingNewHasGeography)
            #expect(!pendingNew.onlineText.contains("Controlled tiles"))
            #expect(pendingNew.focusedIdentity == initial.focusedIdentity)
            await transport.release()
            let ready = try await frames.wait(after: pendingNew.sequence) {
                $0.onlineReady && $0.onlineText.contains("Lon=103.888")
            }
            #expect(await transport.paths(after: 2) == movedPaths)
            #expect(ready.focusedIdentity == initial.focusedIdentity)
        }
    }

    // Independent addresses for the known 100x27 drawing allocation at z14,
    // including both north/south rows and every longitude column after the pan.
    private var worldPaths: Set<String> {
        ["/1/0/0.pbf", "/1/0/1.pbf", "/1/1/0.pbf", "/1/1/1.pbf"]
    }
    private var initialPaths: Set<String> {
        ["/14/12918/8132.pbf", "/14/12918/8133.pbf", "/14/12919/8132.pbf", "/14/12919/8133.pbf"]
    }
    private var movedPaths: Set<String> {
        ["/14/12919/8132.pbf", "/14/12919/8133.pbf", "/14/12920/8132.pbf", "/14/12920/8133.pbf"]
    }
}

private actor OnlineTransport {
    private let source: OpenMapTilesSource
    private var held: Bool
    private var fails: Bool
    private var urls: [URL] = []
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var factoryCalls = 0
    var count: Int { urls.count }

    init(held: Bool, fails: Bool) throws {
        self.held = held
        self.fails = fails
        let url = URL(string: "https://example.test")!
        source = try OpenMapTilesSource(template: "https://example.test/{z}/{x}/{y}.pbf", zoomRange: 1...14,
            metadata: MapSourceMetadata(attribution: "Controlled tiles", license: "Fixture license",
                                        licenseURL: url, sourceURL: url, sourceRevision: "test-revision"))
    }

    func makeLoader() -> MapTileLoader {
        factoryCalls += 1
        return MapTileLoader(source: source, transport: { url, _ in try await self.fetch(url) })
    }

    private func fetch(_ url: URL) async throws -> MapHTTPClient.Response {
        urls.append(url)
        if held { await withCheckedContinuation { pending.append($0) } }
        if fails { throw MapTileLoader.LoadingError.httpStatus(503) }
        // An empty protobuf message is a valid MVT with no supported layers.
        // No-store ensures resume/refresh assertions observe acquisition itself.
        return MapHTTPClient.Response(data: Data(), headers: ["cache-control": "no-store"])
    }

    func setFailure(_ value: Bool) { fails = value }

    func release(keepingHeld: Bool = false) {
        held = keepingHeld
        let continuations = pending
        pending = []
        for continuation in continuations { continuation.resume() }
    }

    func orderedPaths(after count: Int = 0) -> [String] { urls.dropFirst(count).map(\.path) }
    func paths(after count: Int = 0) -> Set<String> { Set(orderedPaths(after: count)) }

    func waitForRequests(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while urls.count < count, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard urls.count >= count else { throw TransportTimeout() }
    }

    private struct TransportTimeout: Error {}
}

private struct OnlineTestApp {
    let transport: OnlineTransport?
    let startsWorld: Bool
    let overlays: MapOverlays
    nonisolated init() { transport = nil; startsWorld = false; overlays = .empty }
    nonisolated init(transport: OnlineTransport, startsWorld: Bool, overlays: MapOverlays) {
        self.transport = transport; self.startsWorld = startsWorld; self.overlays = overlays
    }
}

extension OnlineTestApp: App {
    var body: some Scene {
        WindowGroup(id: "online-map-tests") {
            if let transport {
                OnlineTestView(transport: transport, startsWorld: startsWorld, overlays: overlays)
            }
        }.exitOnKeys([])
    }
}

@MainActor
private struct OnlineTestView {
    let transport: OnlineTransport
    let overlays: MapOverlays
    @State private var camera: MapCamera
    @State private var selection: String?
    @State private var detail: MapDetail = .minimal
    @State private var light = false
    @State private var retry = 0
    @State private var barrier = 0
    @State private var activation = "none"

    init(transport: OnlineTransport, startsWorld: Bool, overlays: MapOverlays) {
        self.transport = transport
        self.overlays = overlays
        _camera = State(wrappedValue: (startsWorld ? MapFixtures.Scene.world : .street).camera)
        _selection = State(wrappedValue: nil)
    }
}

extension OnlineTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnlineMapContent(camera: $camera, selection: $selection, overlays: overlays,
                             detail: detail, fills: true, labels: true, retry: retry, activate: { activation = $0.id },
                             makeLoader: { [transport] in await transport.makeLoader() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(String(format: "Lon=%.3f Span=%.4f", camera.center.longitude, camera.longitudeSpan))
                .frame(height: 1, alignment: .leading)
            Text("Detail=\(detail.rawValue) Theme=\(light ? "light" : "default") B=\(barrier) S=\(selection ?? "nil") A=\(activation)")
                .frame(height: 1, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("b"): barrier += 1
            case .character("d"): detail = .source
            case .character("t"): light.toggle()
            case .character("e"): retry += 1
            case .character("w"): camera = camera.longitudeSpan >= 45 ? MapFixtures.Scene.street.camera : MapFixtures.Scene.world.camera
            default: return .ignored
            }
            return .handled
        }
        .chioTheme(light ? .light : .default)
    }
}

@MainActor
private func withOnlineScene(
    held: Bool = false, startsWorld: Bool = false, fails: Bool = false, markers: Bool = false,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, OnlineFrames, OnlineTransport) async throws -> Void
) async throws {
    let frames = OnlineFrames()
    let surface = HostedRasterSurface(surfaceSize: CellSize(width: 100, height: 32), appearance: .fallback,
                                      onFrame: { frames.latest = $0 })
    let transport = try OnlineTransport(held: held, fails: fails)
    let overlays = markers ? try MapOverlays(markers: [
        MapMarker(id: "place", coordinate: MapFixtures.Scene.street.camera.center, title: "Online place")
    ]) : .empty
    let session = try HostedSceneSession(for: OnlineTestApp(transport: transport, startsWorld: startsWorld, overlays: overlays),
                                        sceneID: "online-map-tests", surface: surface)
    let run = Task { try await session.start() }
    do {
        try await perform(session, surface, frames, transport)
        await transport.release()
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        await transport.release()
        session.stop()
        _ = await run.result
        throw error
    }
}

@MainActor
private final class OnlineFrames {
    var latest: SemanticHostFrame?

    func wait(after sequence: UInt64? = nil,
              matching predicate: (SemanticHostFrame) -> Bool) async throws -> SemanticHostFrame {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let latest, sequence.map({ latest.sequence > $0 }) ?? true, predicate(latest) { return latest }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FrameTimeout(text: latest?.onlineText ?? "No frame received")
    }

    private struct FrameTimeout: Error, CustomStringConvertible {
        let text: String
        var description: String { "Timed out waiting for online map frame:\n\(text)" }
    }
}

private extension SemanticHostFrame {
    var onlineText: String { raster.lines.joined(separator: "\n") }
    var onlineReady: Bool { onlineText.contains("Online · z14") }
    var onlineHasGeography: Bool {
        onlineText.unicodeScalars.contains { (0x2801...0x28FF).contains($0.value) }
    }
}
