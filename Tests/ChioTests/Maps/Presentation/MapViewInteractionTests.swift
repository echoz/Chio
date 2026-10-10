import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct MapViewInteractionTests {
    @Test("An absent source retains allocation, controls and native focus when geographic data arrives")
    func sourceReadiness() async throws {
        try await withMapScene(markers: true, startsWithoutSource: true) { session, _, recorder in
            let unloaded = try await recorder.wait(description: "an unloaded map still reports its drawing allocation and receives focus") {
                $0.mapContains("No map source loaded") && $0.mapContains("Viewport=60x18")
                    && $0.focusedIdentity != nil
            }
            #expect(!unloaded.mapHasGeography)
            #expect(!unloaded.mapContains("credit"))
            #expect(!unloaded.mapContains("Fixture license"))
            #expect(unloaded.semantics.focusRegions.count == 2)
            session.send([.key(.arrowRight), .key(.character("+")), .key(.character("n")),
                          .key(.return), .key(.character("b"), modifiers: .ctrl)])
            let controlled = try await recorder.wait(after: unloaded.sequence, description: "camera, marker selection and activation work before loading") {
                $0.mapContains("No map source loaded") && $0.mapContains("Selection=near CW=3 SW=1")
                    && $0.mapContains("A=near B=1")
            }
            #expect(controlled.mapContains("Lon=-20.000 Lat=-10.000 Span=70.000"))
            #expect(controlled.focusedIdentity == unloaded.focusedIdentity)
            session.send([.key(.character("a"), modifiers: .ctrl), .key(.character("b"), modifiers: .ctrl)])
            let loaded = try await recorder.wait(after: controlled.sequence, description: "the supplied source loads into the same native map with unchanged bindings") {
                $0.mapReady && $0.mapContains("Alpha credit") && $0.mapContains("B=2")
                    && $0.mapHasGeography
            }
            #expect(loaded.mapContains("Lon=-20.000 Lat=-10.000 Span=70.000"))
            #expect(loaded.mapContains("Selection=near CW=3 SW=1"))
            #expect(loaded.mapContains("Viewport=60x18"))
            #expect(loaded.focusedIdentity == unloaded.focusedIdentity)
            #expect(loaded.semantics.focusRegions.count == 2)
            session.send([.key(.character("a"), modifiers: .ctrl), .key(.character("b"), modifiers: .ctrl)])
            let cleared = try await recorder.wait(after: loaded.sequence, description: "clearing the loaded source removes its geography and metadata") {
                $0.mapContains("No map source loaded") && $0.mapContains("B=3")
            }
            #expect(!cleared.mapHasGeography)
            #expect(!cleared.mapContains("Alpha"))
            #expect(!cleared.mapContains("Fixture license"))
            #expect(cleared.focusedIdentity == unloaded.focusedIdentity)
        }
    }

    @Test("A supplied map frame owns its allocation and preserves focus through compact recovery")
    func allocationAndFallback() async throws {
        try await withMapScene { session, surface, recorder in
            let initial = try await recorder.wait(description: "ready map in a 60 by 20 frame inside the larger terminal") {
                $0.mapReady && $0.mapContains("Alpha") && $0.focusedIdentity != nil
            }
            #expect(initial.raster.size == CellSize(width: 100, height: 34))
            #expect(initial.semantics.focusRegions.count == 2)
            #expect(initial.raster.cells.enumerated().allSatisfy { row, cells in
                cells.enumerated().allSatisfy { column, cell in
                    !cell.character.unicodeScalars.contains { (0x2801...0x28FF).contains($0.value) }
                        || (row < 18 && column < 60)
                }
            })
            session.send([.key(.character("c"), modifiers: .ctrl), .key(.character("b"), modifiers: .ctrl)])
            let compact = try await recorder.wait(after: initial.sequence, description: "the supplied compact frame falls back despite ample terminal space") {
                $0.mapContains("More room for the map") && $0.mapContains("B=1")
            }
            #expect(!compact.mapHasGeography)
            #expect(compact.mapContains("Lon=0.000 Lat=0.000 Span=100.000"))
            #expect(compact.mapContains("Selection=nil CW=0 SW=0"))
            #expect(compact.focusedIdentity == initial.focusedIdentity)
            session.send([.key(.arrowRight), .key(.character("+")),
                          .key(.character("c"), modifiers: .ctrl), .key(.character("b"), modifiers: .ctrl)])
            let resumed = try await recorder.wait(after: compact.sequence, description: "compact input and expansion preserve authoritative camera changes") {
                $0.mapReady && $0.mapContains("B=2")
                    && $0.mapContains("Lon=12.000 Lat=0.000 Span=70.000")
            }
            #expect(resumed.mapContains("Selection=nil CW=2 SW=0"))
            #expect(resumed.focusedIdentity == initial.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 76, height: 30))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: resumed.sequence, description: "terminal resize preserves the framed map and native focus") {
                $0.raster.size == CellSize(width: 76, height: 30) && $0.mapReady
            }
            #expect(resized.mapContains("Lon=12.000 Lat=0.000 Span=70.000"))
            #expect(resized.focusedIdentity == initial.focusedIdentity)
        }
    }

    @Test("Batched map input reads retained camera storage and respects rejected binding writes")
    func batchedCameraBindings() async throws {
        for rejectsWrites in [false, true] {
            try await withMapScene(rejectsCameraWrites: rejectsWrites) { session, _, recorder in
                let initial = try await recorder.wait(description: "map focus before batched camera changes") {
                    $0.mapReady && $0.focusedIdentity != nil
                }
                session.send([.key(.arrowRight), .key(.arrowRight), .key(.character("+")),
                              .key(.arrowRight), .key(.character("b"), modifiers: .ctrl)])
                let changed = try await recorder.wait(after: initial.sequence, description: "all camera proposals and the input barrier were delivered") {
                    $0.mapContains("B=1") && $0.mapContains("CW=4")
                }
                #expect(changed.mapContains(rejectsWrites
                    ? "Lon=0.000 Lat=0.000 Span=100.000"
                    : "Lon=32.400 Lat=0.000 Span=70.000"))
                #expect(changed.focusedIdentity == initial.focusedIdentity)
                session.send([.key(.character("e"), modifiers: .ctrl), .key(.arrowLeft),
                              .key(.character("b"), modifiers: .ctrl)])
                let replaced = try await recorder.wait(after: changed.sequence, description: "an external replacement is authoritative before the next arrow") {
                    $0.mapContains("B=2") && $0.mapContains("CW=5")
                }
                #expect(replaced.mapContains(rejectsWrites
                    ? "Lon=30.000 Lat=0.000 Span=80.000"
                    : "Lon=20.400 Lat=0.000 Span=80.000"))
            }
        }
    }

    @Test("Marker traversal includes offscreen input order, activation and one native focus stop")
    func markerSelectionAndFocus() async throws {
        try await withMapScene(markers: true) { session, _, recorder in
            let initial = try await recorder.wait(description: "map focus with no selected marker") {
                $0.mapReady && $0.mapContains("Selection=nil") && $0.focusedIdentity != nil
            }
            session.send([.key(.character("p")), .key(.return), .key(.character("b"), modifiers: .ctrl)])
            let previous = try await recorder.wait(after: initial.sequence, description: "Previous selects the final offscreen marker and Return activates it") {
                $0.mapContains("Selection=far CW=1 SW=1") && $0.mapContains("A=far B=1")
            }
            #expect(previous.mapContains("Lon=150.000 Lat=10.000 Span=100.000"))
            session.send([.key(.character("n")), .key(.return), .key(.character("b"), modifiers: .ctrl)])
            let next = try await recorder.wait(after: previous.sequence, description: "Next wraps in authored marker order and keeps zoom") {
                $0.mapContains("Selection=near CW=2 SW=2") && $0.mapContains("A=near B=2")
            }
            #expect(next.mapContains("Lon=-20.000 Lat=-10.000 Span=100.000"))
            #expect(next.focusedIdentity == initial.focusedIdentity)
            #expect(next.semantics.focusRegions.count == 2)
            session.send(.key(.tab))
            let adjacent = try await recorder.wait(after: next.sequence, description: "one Tab leaves the map for an adjacent native button") {
                $0.mapButtonFocused("Adjacent")
            }
            session.send([.key(.return), .key(.arrowRight), .key(.character("b"), modifiers: .ctrl)])
            let clicked = try await recorder.wait(after: adjacent.sequence, description: "the adjacent native action receives Return and map arrows do not write") {
                $0.mapContains("Clicks=1") && $0.mapContains("B=3")
            }
            #expect(clicked.mapContains("Selection=near CW=2 SW=2"))
            // Unclaimed Right is native directional focus navigation: it moves
            // from the narrow button back to the map, without panning it.
            #expect(clicked.focusedIdentity == initial.focusedIdentity)
            session.send(.key(.tab))
            let adjacentAgain = try await recorder.wait(after: clicked.sequence, description: "Tab returns to the adjacent control") {
                $0.mapButtonFocused("Adjacent")
            }
            session.send(.key(.tab, modifiers: .shift))
            let returned = try await recorder.wait(after: adjacentAgain.sequence, description: "Shift-Tab returns to the same native map focus stop") {
                $0.focusedIdentity == initial.focusedIdentity
            }
            #expect(returned.mapContains("Selection=near"))
        }
    }

    @Test("Marker glyph pointer selection respects accepted and rejected selection bindings",
          arguments: [false, true])
    func pointerSelection(rejectsSelection: Bool) async throws {
        try await withMapScene(rejectsSelectionWrites: rejectsSelection, markers: true) { session, _, recorder in
            let initial = try await recorder.wait(description: "the unselected visible marker is ready for pointer input") {
                $0.mapReady && $0.mapMarkerPoint != nil && $0.focusedIdentity != nil
            }
            var preceding = initial
            if rejectsSelection {
                session.send([.key(.character("n")), .key(.character("p")), .key(.return),
                              .key(.character("b"), modifiers: .ctrl)])
                preceding = try await recorder.wait(after: initial.sequence, description: "rejected Next and Previous do not select, pan or activate") {
                    $0.mapContains("Selection=nil CW=0 SW=2") && $0.mapContains("A=none B=1")
                }
                #expect(preceding.mapContains("Lon=0.000 Lat=0.000 Span=100.000"))
            }
            session.send(.key(.tab))
            let adjacent = try await recorder.wait(after: preceding.sequence, description: "pointer selection starts with the adjacent native button focused") {
                $0.mapButtonFocused("Adjacent") && $0.mapMarkerPoint != nil
            }
            let point = try #require(adjacent.mapMarkerPoint)
            session.send([
                .mouse(MouseEvent(kind: .down(.primary), location: .cellFallback(point))),
                .mouse(MouseEvent(kind: .up(.primary), location: .cellFallback(point))),
                .key(.character("b"), modifiers: .ctrl),
            ])
            let selected = try await recorder.wait(after: adjacent.sequence, description: "the glyph click proposes selection and restores native map focus") {
                $0.mapContains(rejectsSelection ? "Selection=nil CW=0 SW=3" : "Selection=near CW=1 SW=1")
                    && $0.mapContains(rejectsSelection ? "A=none B=2" : "A=none B=1")
                    && $0.focusedIdentity == initial.focusedIdentity
            }
            #expect(selected.mapContains(rejectsSelection
                ? "Lon=0.000 Lat=0.000 Span=100.000"
                : "Lon=-20.000 Lat=-10.000 Span=100.000"))
            #expect(selected.mapContains("Clicks=0"))
            session.send([.key(.return), .key(.character("b"), modifiers: .ctrl)])
            let activated = try await recorder.wait(after: selected.sequence, description: "Return activates only a retained valid marker selection") {
                $0.mapContains(rejectsSelection ? "A=none B=3" : "A=near B=2")
            }
            #expect(activated.mapContains(rejectsSelection ? "Selection=nil CW=0 SW=3" : "Selection=near CW=1 SW=1"))
            #expect(activated.focusedIdentity == initial.focusedIdentity)
        }
    }

    @Test("The outer cells of a selected Braille ring retain native pointer selection and focus")
    func selectedRingPointer() async throws {
        try await withMapScene(markers: true) { session, _, recorder in
            let initial = try await recorder.wait(description: "ready map before selecting a ring") { $0.mapReady }
            session.send([.key(.character("n")), .key(.character("b"), modifiers: .ctrl)])
            let selected = try await recorder.wait(after: initial.sequence, description: "selected ring is drawn") {
                $0.mapReady && $0.mapContains("Selection=near CW=1 SW=1") && !$0.mapSelectedRingCells.isEmpty
            }
            session.send(.key(.tab))
            let adjacent = try await recorder.wait(after: selected.sequence, description: "adjacent button focused before ring click") {
                $0.mapButtonFocused("Adjacent") && !$0.mapSelectedRingCells.isEmpty
            }
            let cells = adjacent.mapSelectedRingCells
            #expect(Set(cells.map(\.y)).count == 2)
            // After centering, the marker centre is in the bottom row. Click the
            // uppermost lit cell, outside the old one-cell marker hit region.
            let point = try #require(cells.first)
            #expect(point.y < cells.map(\.y).max()!)
            session.send([
                .mouse(MouseEvent(kind: .down(.primary), location: .cellFallback(point))),
                .mouse(MouseEvent(kind: .up(.primary), location: .cellFallback(point))),
                .key(.character("b"), modifiers: .ctrl),
            ])
            let clicked = try await recorder.wait(after: adjacent.sequence, description: "outer ring click restores map focus") {
                $0.mapContains("Selection=near CW=2 SW=2") && $0.mapContains("B=2")
                    && $0.focusedIdentity == initial.focusedIdentity
            }
            #expect(clicked.mapContains("Clicks=0"))
            #expect(clicked.mapContains("A=none"))
        }
    }

    @Test("External unknown selection survives rendering, resizing and activation without camera repair")
    func unknownSelection() async throws {
        try await withMapScene(markers: true) { session, _, recorder in
            let initial = try await recorder.wait(description: "ready map before application-owned selection replacement") { $0.mapReady }
            session.send([.key(.character("u"), modifiers: .ctrl), .key(.return),
                          .key(.character("c"), modifiers: .ctrl), .key(.character("b"), modifiers: .ctrl)])
            let unknown = try await recorder.wait(after: initial.sequence, description: "unknown application selection is retained through the compact state") {
                $0.mapContains("Selection=unknown CW=0 SW=0") && $0.mapContains("B=1")
                    && $0.mapContains("More room for the map")
            }
            #expect(unknown.mapContains("Lon=0.000 Lat=0.000 Span=100.000"))
            #expect(unknown.mapContains("A=none"))
            session.send([.key(.character("c"), modifiers: .ctrl), .key(.character("b"), modifiers: .ctrl)])
            let restored = try await recorder.wait(after: unknown.sequence, description: "expanding does not reconcile an unknown ID or change its camera") {
                $0.mapReady && $0.mapContains("B=2") && $0.mapContains("Selection=unknown CW=0 SW=0")
            }
            #expect(restored.mapContains("Lon=0.000 Lat=0.000 Span=100.000"))
            session.send([.key(.character("n")), .key(.character("b"), modifiers: .ctrl)])
            _ = try await recorder.wait(after: restored.sequence, description: "explicit Next starts from the first input marker for unknown selection") {
                $0.mapContains("Selection=near CW=1 SW=1") && $0.mapContains("B=3")
            }
        }
    }

    @Test("Source, detail and allocation replacements remove previous geography before resuming")
    func sourceDetailAndResize() async throws {
        try await withMapScene { session, _, recorder in
            let initial = try await recorder.wait(description: "Alpha source is prepared and labelled") {
                $0.mapReady && $0.mapContains("Alpha") && $0.mapHasGeography
            }
            session.send([.key(.character("s"), modifiers: .ctrl), .key(.character("d"), modifiers: .ctrl),
                          .key(.character("c"), modifiers: .ctrl), .key(.character("e"), modifiers: .ctrl),
                          .key(.character("b"), modifiers: .ctrl)])
            let invalidated = try await recorder.wait(after: initial.sequence, description: "replacement source and camera enter compact fallback without old geography") {
                $0.mapContains("B=1") && $0.mapContains("More room for the map") && $0.mapContains("Beta credit")
            }
            #expect(!invalidated.mapHasGeography)
            #expect(!invalidated.mapContains("Alpha"))
            #expect(invalidated.mapContains("Lon=30.000 Lat=0.000 Span=80.000"))
            session.send([.key(.character("c"), modifiers: .ctrl), .key(.character("b"), modifiers: .ctrl)])
            let silhouette = try await recorder.wait(after: invalidated.sequence, description: "resumed silhouette excludes the replacement road") {
                $0.mapReady && $0.mapContains("B=2") && $0.mapContains("Beta credit")
            }
            #expect(!silhouette.mapHasGeography)
            #expect(!silhouette.mapContains("Alpha"))
            session.send([.key(.character("d"), modifiers: .ctrl), .key(.character("b"), modifiers: .ctrl)])
            let ready = try await recorder.wait(after: silhouette.sequence, description: "source detail prepares only the replacement road and current camera") {
                $0.mapReady && $0.mapContains("B=3") && $0.mapContains("Beta road") && $0.mapHasGeography
            }
            #expect(!ready.mapContains("Alpha"))
            #expect(ready.focusedIdentity == initial.focusedIdentity)
        }
    }
}

private struct MapConsumerFixtures {
    let alpha: MapSource
    let beta: MapSource
    let camera: MapCamera
    let replacementCamera: MapCamera
    let overlays: MapOverlays

    init(markers: Bool) throws {
        let url = URL(string: "https://example.com/offline-maps")!
        func source(_ title: String, feature: MapFeature) throws -> MapSource {
            try MapSource(dataset: MapDataset(features: [feature]),
                          metadata: MapSourceMetadata(attribution: "\(title) credit", license: "Fixture license",
                                                      licenseURL: url, sourceURL: url, sourceRevision: "fixture-1"),
                          coverage: .worldwide)
        }
        let ring = try MapRing(coordinates: [MapCoordinate(latitude: -20, longitude: -35),
                                            MapCoordinate(latitude: -20, longitude: 35),
                                            MapCoordinate(latitude: 20, longitude: 35),
                                            MapCoordinate(latitude: 20, longitude: -35),
                                            MapCoordinate(latitude: -20, longitude: -35)])
        alpha = try source("Alpha", feature: MapFeature(id: "alpha", kind: .land, name: "Alpha",
                                                       geometry: .polygon(MapPolygon(rings: [ring]))))
        beta = try source("Beta", feature: MapFeature(id: "beta", kind: .primaryRoad, name: "Beta road",
                                                     geometry: .polyline(MapPolyline(coordinates: [
                                                        MapCoordinate(latitude: 0, longitude: -35),
                                                        MapCoordinate(latitude: 0, longitude: 60)]))))
        camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 100)
        replacementCamera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 30), longitudeSpan: 80)
        overlays = markers ? try MapOverlays(markers: [
            MapMarker(id: "near", coordinate: MapCoordinate(latitude: -10, longitude: -20), title: "Nearby"),
            MapMarker(id: "far", coordinate: MapCoordinate(latitude: 10, longitude: 150), title: "Offscreen")
        ]) : .empty
    }
}

private struct MapConsumerTestApp {
    let fixtures: MapConsumerFixtures?
    let rejectsCameraWrites: Bool
    let rejectsSelectionWrites: Bool
    let startsWithoutSource: Bool

    nonisolated init() {
        fixtures = nil; rejectsCameraWrites = false; rejectsSelectionWrites = false; startsWithoutSource = false
    }
    nonisolated init(fixtures: MapConsumerFixtures, rejectsCameraWrites: Bool, rejectsSelectionWrites: Bool,
                     startsWithoutSource: Bool) {
        self.fixtures = fixtures
        self.rejectsCameraWrites = rejectsCameraWrites
        self.rejectsSelectionWrites = rejectsSelectionWrites
        self.startsWithoutSource = startsWithoutSource
    }
}

extension MapConsumerTestApp: App {
    var body: some Scene {
        WindowGroup(id: "map-consumer-tests") {
            if let fixtures {
                MapConsumerTestView(fixtures: fixtures, rejectsCameraWrites: rejectsCameraWrites,
                                    rejectsSelectionWrites: rejectsSelectionWrites,
                                    startsWithoutSource: startsWithoutSource)
            }
        }.exitOnKeys([])
    }
}

@MainActor
private struct MapConsumerTestView {
    let fixtures: MapConsumerFixtures
    let rejectsCameraWrites: Bool
    let rejectsSelectionWrites: Bool
    @State private var camera: MapCamera
    @State private var selection: String?
    @State private var cameraWrites = 0
    @State private var selectionWrites = 0
    @State private var barrier = 0
    @State private var activation = "none"
    @State private var clicks = 0
    @State private var compact = false
    @State private var secondSource = false
    @State private var hasSource: Bool
    @State private var viewport: MapViewport?
    @State private var detail: MapDetail = .source

    init(fixtures: MapConsumerFixtures, rejectsCameraWrites: Bool, rejectsSelectionWrites: Bool,
         startsWithoutSource: Bool) {
        self.fixtures = fixtures
        self.rejectsCameraWrites = rejectsCameraWrites
        self.rejectsSelectionWrites = rejectsSelectionWrites
        _camera = State(wrappedValue: fixtures.camera)
        _selection = State(wrappedValue: nil)
        _hasSource = State(wrappedValue: !startsWithoutSource)
    }

    private var source: MapSource? {
        guard hasSource else { return nil }
        return secondSource ? fixtures.beta : fixtures.alpha
    }

    private var controlledCamera: Binding<MapCamera> {
        let storage = $camera
        let count = $cameraWrites
        return Binding(get: { storage.wrappedValue }, set: { proposed in
            count.wrappedValue += 1
            if !rejectsCameraWrites { storage.wrappedValue = proposed }
        })
    }

    private var controlledSelection: Binding<String?> {
        let storage = $selection
        let count = $selectionWrites
        return Binding(get: { storage.wrappedValue }, set: { proposed in
            count.wrappedValue += 1
            if !rejectsSelectionWrites { storage.wrappedValue = proposed }
        })
    }
}

extension MapConsumerTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MapView(source: source,
                    camera: controlledCamera, selection: controlledSelection,
                    overlays: fixtures.overlays, detail: detail)
                .onActivate { activation = $0.id }
                .onViewportChange { viewport = $0 }
                .frame(width: compact ? 30 : 60, height: compact ? 12 : 20, alignment: .topLeading)
            Button("Adjacent") { clicks += 1 }
            Text(String(format: "Lon=%.3f Lat=%.3f Span=%.3f", camera.center.longitude,
                        camera.center.latitude, camera.longitudeSpan))
            Text("Selection=\(selection ?? "nil") CW=\(cameraWrites) SW=\(selectionWrites)")
            Text("A=\(activation) B=\(barrier) Clicks=\(clicks)")
            Text(viewport.map { "Viewport=\($0.columns)x\($0.rows)" } ?? "Viewport=nil")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("b"): barrier += 1
            case .character("c"): compact.toggle()
            case .character("e"): camera = fixtures.replacementCamera
            case .character("u"): selection = "unknown"
            case .character("s"): secondSource.toggle()
            case .character("a"): hasSource.toggle()
            case .character("d"): detail = detail == .source ? .silhouette : .source
            default: return .ignored
            }
            return .handled
        }
    }
}

@MainActor
private func withMapScene(
    rejectsCameraWrites: Bool = false, rejectsSelectionWrites: Bool = false, markers: Bool = false,
    startsWithoutSource: Bool = false,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 34), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let fixtures = try MapConsumerFixtures(markers: markers)
    let session = try HostedSceneSession(for: MapConsumerTestApp(fixtures: fixtures, rejectsCameraWrites: rejectsCameraWrites,
        rejectsSelectionWrites: rejectsSelectionWrites, startsWithoutSource: startsWithoutSource),
                                        sceneID: "map-consumer-tests", surface: surface)
    let run = Task { try await session.start() }
    do {
        try await perform(session, surface, recorder)
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        _ = await run.result
        throw error
    }
}

private extension SemanticHostFrame {
    func mapContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    var mapHasGeography: Bool {
        raster.lines.joined().unicodeScalars.contains { (0x2801...0x28FF).contains($0.value) }
    }
    var mapReady: Bool {
        mapContains("credit") && !mapContains("Preparing map") && !mapContains("More room for the map")
            && !mapContains("Too much map detail")
    }
    var mapMarkerPoint: CellPoint? {
        for (row, cells) in raster.cells.enumerated() {
            if let column = cells.firstIndex(where: { $0.character == "⠶" }) {
                return CellPoint(x: column, y: row)
            }
        }
        return nil
    }
    var mapSelectedRingCells: [CellPoint] {
        raster.cells.enumerated().flatMap { row, cells in
            cells.enumerated().compactMap { column, cell in
                guard cell.style?.foregroundColor == ChioTheme.default.colors.warning,
                      let scalar = cell.character.unicodeScalars.first,
                      (0x2801...0x28FF).contains(scalar.value) else { return nil }
                return CellPoint(x: column, y: row)
            }
        }
    }
    func mapButtonFocused(_ title: String) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.role == .button && $0.label == title && $0.identity == focusedIdentity
        }
    }
}
