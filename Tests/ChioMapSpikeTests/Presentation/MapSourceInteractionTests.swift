@testable import ChioMapSpike
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct MapSourceInteractionTests {
    @Test("Street source changes preserve the camera, detail, theme, fills, labels and native focus")
    func retainedPresentation() async throws {
        let fixtures = try MapFixtures.load()
        let frames = Frames()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                          onFrame: { frames.latest = $0 })
        let app = MapSpikeApplication(fixtures: fixtures, scene: .street, appearance: .default)
        let session = try HostedSceneSession(for: app, sceneID: WindowIdentifier("Chio map rendering spike"), surface: surface)
        let run = Task { try await session.start() }
        do {
            let initial = try await frames.wait {
                $0.text.contains("Overpass") && $0.hasGeography && $0.focusedIdentity != nil
            }
            session.send([.key(.arrowRight), .key(.character("+")), .key(.character("]")),
                          .key(.character("t")), .key(.character("f")), .key(.character("l"))])
            let moved = try await frames.wait(after: initial.sequence) {
                $0.text.contains("Center 1.289, 103.870 · span 0.0210°")
                    && $0.text.contains("detail 3/4 abstract · light") && $0.hasGeography
            }
            session.send(.key(.character("p")))
            let switched = try await frames.wait(after: moved.sequence) {
                $0.text.contains("OpenFreeMap") && $0.hasGeography
            }
            #expect(switched.text.contains("Center 1.289, 103.870 · span 0.0210°"))
            #expect(switched.text.contains("detail 3/4 abstract · light"))
            #expect(switched.focusedIdentity == initial.focusedIdentity)
            #expect(switched.raster != moved.raster)
            #expect(switched.raster.cells[4..<24].allSatisfy { row in
                row[1..<99].allSatisfy { cell in
                    // Fills and labels were disabled before changing provider.
                    cell.style?.backgroundColor == ChioTheme.light.colors.surface
                        && cell.character.unicodeScalars.allSatisfy { $0.value == 32 || (0x2800...0x28FF).contains($0.value) }
                }
            })
            session.send([.key(.character("p")), .key(.character("p"))])
            let roundTrip = try await frames.wait(after: switched.sequence) { $0.text.contains("OpenFreeMap") }
            #expect(roundTrip.raster == switched.raster)
            #expect(roundTrip.focusedIdentity == initial.focusedIdentity)

            surface.updateSurfaceSize(.init(width: 60, height: 26))
            session.requestSurfaceRefresh()
            let narrow = try await frames.wait(after: roundTrip.sequence) {
                $0.raster.size == CellSize(width: 60, height: 26) && $0.hasGeography
            }
            #expect(narrow.text.contains("OpenFreeMap · detail 3/4 abstract · light"))
            #expect(narrow.text.contains("p source"))
            #expect(narrow.text.contains("q quit"))
            #expect(narrow.focusedIdentity == initial.focusedIdentity)
            session.send(Array(repeating: .key(.arrowRight), count: 12))
            let outside = try await frames.wait(after: narrow.sequence) { $0.text.contains("Outside coverage") }
            #expect(outside.text.contains("Outside coverage · OpenFreeMap · 3/4 abstract; r reset"))
            #expect(outside.focusedIdentity == initial.focusedIdentity)
            session.send(.key(.character("r")))
            let reset = try await frames.wait(after: outside.sequence) {
                $0.text.contains("Center 1.289, 103.866 · span 0.0300°") && !$0.text.contains("Outside")
            }
            #expect(reset.text.contains("OpenFreeMap · detail 3/4 abstract · light"))
            #expect(reset.hasGeography)
            #expect(reset.focusedIdentity == initial.focusedIdentity)
            session.send([.key(.arrowRight), .key(.character("+"))])
            let restored = try await frames.wait(after: reset.sequence) {
                $0.text.contains("Center 1.289, 103.870 · span 0.0210°") && !$0.text.contains("Outside")
            }
            #expect(restored.raster == narrow.raster)
            surface.updateSurfaceSize(.init(width: 100, height: 30))
            session.requestSurfaceRefresh()
            let expanded = try await frames.wait(after: restored.sequence) { $0.raster.size == CellSize(width: 100, height: 30) }
            #expect(expanded.raster == switched.raster)

            session.send(.key(.space))
            let world = try await frames.wait(after: expanded.sequence) { $0.text.contains("map spike · World") }
            #expect(world.text.contains("Natural Earth"))
            #expect(world.text.contains("detail 3/4 abstract · light"))
            #expect(world.focusedIdentity == initial.focusedIdentity)
            session.send(.key(.space))
            let street = try await frames.wait(after: world.sequence) {
                $0.text.contains("Singapore") && $0.text.contains("OpenFreeMap") && $0.hasGeography
            }
            #expect(street.text.contains("detail 3/4 abstract · light"))
            #expect(street.focusedIdentity == initial.focusedIdentity)
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    @Test("The CLI source choice reaches snapshots and leaves world presentation unchanged")
    func launchSource() throws {
        #expect(try MapSpikeCommand.parse([]).source == .overpass)
        #expect(try MapSpikeCommand.parse(["--source", "openfreemap"]).source == .openfreemap)
        #expect(throws: (any Error).self) { try MapSpikeCommand.parse(["--source", "unknown"]) }
        #expect(throws: (any Error).self) { try MapSpikeCommand.parse(["--map", "unknown"]) }
        let command = try MapSpikeCommand.parse(["--map", "street", "--source", "openfreemap",
                                                "--web", "--scene", "Chio map rendering spike"])
        #expect(command.scene == .street && command.source == .openfreemap)
        #expect(command.swiftTUIOptions.web)
        #expect(command.swiftTUIOptions.scene == "Chio map rendering spike")
        let fixtures = try MapFixtures.load()
        func render(_ scene: MapFixtures.Scene, _ source: MapFixtures.StreetSource) -> RasterSurface {
            let view = MapSpikeView(fixtures: fixtures, scene: scene, appearance: .default, streetSource: source)
                .environment(\.terminalSize, CellSize(width: 100, height: 30))
            return DefaultRenderer().render(view, proposal: .init(width: 100, height: 30), frameInstant: .zero).rasterSurface
        }
        let overpass = render(.street, .overpass)
        let tiles = render(.street, .openfreemap)
        #expect(overpass.lines.joined().contains("Overpass"))
        #expect(tiles.lines.joined().contains("OpenFreeMap"))
        #expect(tiles != overpass)
        #expect(render(.world, .overpass) == render(.world, .openfreemap))
    }

    /// Bounded public host observations; the test never reads application state.
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
            var description: String { "Timed out waiting for source frame:\n\(frame)" }
        }
    }
}

private extension SemanticHostFrame {
    var text: String { raster.lines.joined(separator: "\n") }
    var hasGeography: Bool { text.unicodeScalars.contains { (0x2801...0x28FF).contains($0.value) } }
}
