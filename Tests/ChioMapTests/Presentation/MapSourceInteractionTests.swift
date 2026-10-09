@testable import ChioMaps
@testable import Chio
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct MapSourceInteractionTests {
    @Test("A fixed street source retains pan, detail, theme, fill and label options, focus and resize")
    func retainedPresentation() async throws {
        let fixtures = try MapFixtures.load()
        let frames = Frames()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                          onFrame: { frames.latest = $0 })
        let app = MapExampleApplication(fixtures: fixtures, scene: .street, appearance: .default)
        let session = try HostedSceneSession(for: app, sceneID: WindowIdentifier("Chio maps"), surface: surface)
        let run = Task { try await session.start() }
        do {
            let initial = try await frames.wait {
                $0.text.contains("Overpass") && $0.hasGeography && $0.focusedIdentity != nil
            }
            session.send([.key(.arrowRight), .key(.character("+")), .key(.character("]")),
                          .key(.character("t")), .key(.character("f")), .key(.character("l"))])
            let moved = try await frames.wait(after: initial.sequence) {
                $0.text.contains("Center 1.289, 103.870 · span 0.0210°")
                    && $0.text.contains("3/4 abstract · light") && $0.hasGeography
                    && !$0.text.contains("Preparing map")
            }
            #expect(moved.focusedIdentity == initial.focusedIdentity)
            // Provider choice remains the CLI setting. p now traverses locations.
            session.send(.key(.character("p")))
            let selected = try await frames.wait(after: moved.sequence) {
                $0.text.contains("Selected: Singapore Flyer")
                    && $0.text.contains("Center 1.289, 103.863 · span 0.0210°")
                    && !$0.text.contains("Preparing map") && $0.hasGeography
            }
            #expect(selected.text.contains("Overpass · 3/4 abstract · light"))
            #expect(!selected.text.contains("OpenFreeMap"))
            #expect(selected.focusedIdentity == initial.focusedIdentity)
            // Without fills, every geography cell retains the theme surface background.
            // Marker and selected-location cells may carry their own overlay feedback.
            #expect(selected.raster.cells[4..<24].flatMap { Array($0[1..<99]) }
                .filter { $0.character.unicodeScalars.contains { (0x2801...0x28FF).contains($0.value) } }
                .allSatisfy { $0.style?.backgroundColor == ChioTheme.light.colors.surface })
            session.send(.key(.return))
            let activated = try await frames.wait(after: selected.sequence) {
                $0.text.contains("Opened Singapore Flyer")
            }
            surface.updateSurfaceSize(.init(width: 60, height: 26))
            session.requestSurfaceRefresh()
            let narrow = try await frames.wait(after: activated.sequence) {
                $0.raster.size == CellSize(width: 60, height: 26) && $0.hasGeography
                    && !$0.text.contains("Preparing map")
            }
            #expect(narrow.text.contains("Overpass · 3/4 abstract · light"))
            #expect(narrow.text.contains("n/p place"))
            #expect(narrow.text.contains("q quit"))
            #expect(narrow.focusedIdentity == initial.focusedIdentity)
            session.send(Array(repeating: .key(.arrowRight), count: 12))
            let outside = try await frames.wait(after: narrow.sequence) { $0.text.contains("Outside") }
            #expect(outside.text.contains("Overpass"))
            #expect(outside.focusedIdentity == initial.focusedIdentity)
            session.send(.key(.character("r")))
            let reset = try await frames.wait(after: outside.sequence) {
                $0.text.contains("Center 1.289, 103.866 · span 0.0300°")
                    && !$0.text.contains("Outside") && $0.hasGeography
                    && !$0.text.contains("Preparing map")
            }
            #expect(reset.text.contains("Overpass · 3/4 abstract · light"))
            #expect(reset.text.contains("Selected: Singapore Flyer"))
            #expect(reset.focusedIdentity == initial.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 100, height: 30))
            session.requestSurfaceRefresh()
            let expanded = try await frames.wait(after: reset.sequence) {
                $0.raster.size == CellSize(width: 100, height: 30) && $0.hasGeography
                    && !$0.text.contains("Preparing map")
            }
            session.send(.key(.space))
            let world = try await frames.wait(after: expanded.sequence) {
                $0.text.contains("/ maps · World") && $0.hasGeography
                    && !$0.text.contains("Preparing map")
            }
            #expect(world.text.contains("Natural Earth"))
            #expect(world.text.contains("3/4 abstract · light"))
            #expect(world.focusedIdentity == initial.focusedIdentity)
            session.send(.key(.space))
            let street = try await frames.wait(after: world.sequence) {
                $0.text.contains("Singapore") && $0.text.contains("Overpass") && $0.hasGeography
                    && !$0.text.contains("Preparing map")
            }
            #expect(street.text.contains("3/4 abstract · light"))
            #expect(street.text.contains("Selected: None"))
            #expect(street.focusedIdentity == initial.focusedIdentity)
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    @Test("The CLI accepts a fixed offline source choice without coupling world presentation to it")
    func launchSource() throws {
        #expect(try MapExampleCommand.parse([]).source == .overpass)
        #expect(try MapExampleCommand.parse(["--source", "openfreemap"]).source == .openfreemap)
        #expect(throws: (any Error).self) { try MapExampleCommand.parse(["--source", "unknown"]) }
        #expect(throws: (any Error).self) { try MapExampleCommand.parse(["--map", "unknown"]) }
        let command = try MapExampleCommand.parse(["--map", "street", "--source", "openfreemap",
                                                "--web", "--scene", "Chio maps"])
        #expect(command.scene == .street && command.source == .openfreemap)
        #expect(command.swiftTUIOptions.web)
        #expect(command.swiftTUIOptions.scene == "Chio maps")
        let fixtures = try MapFixtures.load()
        func render(_ scene: MapFixtures.Scene, _ source: MapFixtures.StreetSource) -> RasterSurface {
            let view = MapExampleView(fixtures: fixtures, scene: scene, appearance: .default, streetSource: source)
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
