@testable import Chio
@testable import ChioMaps
import Foundation
import SwiftTUIRuntime

/// Every variant consumes the same prepared geometry, camera, allocation and position.
/// This synchronous native raster capture excludes lifecycle and terminal-emulator claims.
@MainActor
enum BrailleMapCapture {
    struct Scene {
        let id: String
        let title: String
        let width: Int
        let height: Int
        let detail: MapDetail
        let source: MapSourceMetadata
        let camera: MapCamera
        let crop: Crop

        struct Crop {
            let x: Int
            let y: Int
            let width: Int
            let height: Int
        }
    }

    struct Comparison {
        let scene: Scene
        let existing: RasterSurface
        let outlines: RasterSurface
        let textured: RasterSurface
        let outlineDrawing: BrailleMapDrawing
        let textureDrawing: BrailleMapDrawing
        let baselineRouteCollisionCells: Int
    }

    static func comparisons() throws -> [Comparison] {
        let fixtures = try MapFixtures.load()
        return try [
            make(id: "singapore", fixture: .street, source: fixtures.streetSource, width: 96, height: 32,
                 detail: .abstract, crop: Scene.Crop(x: 8, y: 12, width: 42, height: 16)),
            make(id: "singapore-narrow", fixture: .street, source: fixtures.streetSource, width: 60, height: 24,
                 detail: .abstract, crop: Scene.Crop(x: 4, y: 8, width: 28, height: 14)),
            make(id: "world", fixture: .world, source: fixtures.worldSource, width: 80, height: 40,
                 detail: .minimal, crop: Scene.Crop(x: 34, y: 5, width: 40, height: 28)),
        ]
    }

    private static func make(id: String, fixture: MapFixtures.Scene, source: MapSource,
                             width: Int, height: Int, detail: MapDetail, crop: Scene.Crop) throws -> Comparison {
        let camera = fixture.camera
        let viewport = try MapViewport(columns: width, rows: height)
        let map = try MapPreparation.prepare(dataset: source.dataset, camera: camera, viewport: viewport, detail: detail)
        let overlays = fixture.overlays
        let routeDataset = try MapDataset(features: overlays.routes.map {
            try MapFeature(id: $0.id, kind: .primaryRoad, geometry: .polyline($0.path))
        })
        let routeMap = try MapPreparation.prepare(dataset: routeDataset, camera: camera, viewport: viewport)
        let position = viewport.project(overlays.markers[1].coordinate, camera: camera)
        let theme = ChioTheme.default
        let existingDrawing = try MapDrawing(map: map, viewport: viewport, colors: theme.colors,
                                             waterColor: theme.map.water, parkColor: theme.map.park,
                                             fills: true, routes: routeMap.lines)
        // Match the shipped selected marker, with all names and labels hidden.
        let existing = DefaultRenderer().render(
            ZStack(alignment: .topLeading) {
                Canvas(existingDrawing, grid: .braille2x4)
                Text("◆").foregroundStyle(theme.colors.accent).background(theme.colors.surface)
                    .frame(width: 1, height: 1).offset(x: Int(floor(position.x)), y: Int(floor(position.y)))
            }.frame(width: width, height: height).background(theme.colors.surface).chioTheme(theme),
            proposal: ProposedSize(width: width, height: height)).rasterSurface
        let outlines = try BrailleMapDrawing(map: map, routes: routeMap.lines, viewport: viewport,
                                             position: position, treatment: .outlines)
        let textured = try BrailleMapDrawing(map: map, routes: routeMap.lines, viewport: viewport,
                                             position: position, treatment: .textured)
        let geography = try MapDrawing(map: map, viewport: viewport, colors: theme.colors,
                                       waterColor: theme.map.water, parkColor: theme.map.park, fills: false)
        let empty = PreparedMap(lines: [], polygons: [], labels: [], statistics: map.statistics)
        let routeOnly = try MapDrawing(map: empty, viewport: viewport, colors: theme.colors,
                                       waterColor: theme.map.water, parkColor: theme.map.park,
                                       fills: false, routes: routeMap.lines)
        let geoRaster = render(geography, viewport: viewport)
        let routeRaster = render(routeOnly, viewport: viewport)
        var collisions = 0
        for y in 0..<height {
            for x in 0..<width {
                let routeMask = mask(routeRaster.cells[y][x].character)
                let extraGeography = mask(geoRaster.cells[y][x].character) & ~routeMask
                if routeMask != 0, extraGeography != 0,
                   existing.cells[y][x].style?.foregroundColor == theme.colors.accent,
                   mask(existing.cells[y][x].character) & extraGeography != 0 { collisions += 1 }
            }
        }
        let scene = Scene(id: id, title: fixture.title, width: width, height: height, detail: detail,
                          source: source.metadata, camera: camera, crop: crop)
        return Comparison(scene: scene, existing: existing, outlines: render(outlines, viewport: viewport),
                          textured: render(textured, viewport: viewport), outlineDrawing: outlines,
                          textureDrawing: textured, baselineRouteCollisionCells: collisions)
    }

    static func render(_ drawing: some CanvasDrawing, viewport: MapViewport) -> RasterSurface {
        let theme = ChioTheme.default
        let view = Canvas(drawing, grid: .braille2x4).frame(width: viewport.columns, height: viewport.rows)
            .background(theme.colors.surface).chioTheme(theme)
        return DefaultRenderer().render(view, proposal: ProposedSize(width: viewport.columns, height: viewport.rows)).rasterSurface
    }

    static func mask(_ character: Character) -> UInt8 {
        guard let scalar = character.unicodeScalars.first, (0x2800...0x28FF).contains(scalar.value) else { return 0 }
        return UInt8(scalar.value - 0x2800)
    }

    static func write(_ comparisons: [Comparison], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(comparisons.map(\.scene)).write(to: directory.appendingPathComponent("manifest.json"))
        for comparison in comparisons {
            for (variant, raster) in [("existing", comparison.existing), ("outlines", comparison.outlines),
                                      ("textured", comparison.textured)] {
                let pixels = raster.cells.map { row in
                    row.map { Pixel(character: String($0.character),
                                    foreground: $0.style?.foregroundColor ?? ChioTheme.default.colors.foreground,
                                    background: $0.style?.backgroundColor ?? ChioTheme.default.colors.surface) }
                }
                try encoder.encode(pixels).write(to: directory.appendingPathComponent("\(comparison.scene.id)-\(variant).json"))
            }
        }
        let metrics = comparisons.map { Metrics(id: $0.scene.id, baselineRouteCollisionCells: $0.baselineRouteCollisionCells,
                                                outlines: $0.outlineDrawing.statistics, textured: $0.textureDrawing.statistics) }
        try encoder.encode(metrics).write(to: directory.appendingPathComponent("metrics.json"))
    }

    private struct Pixel: Encodable {
        let character: String
        let foreground: Color
        let background: Color
    }
    private struct Metrics: Encodable {
        let id: String
        let baselineRouteCollisionCells: Int
        let outlines: BrailleMapDrawing.Statistics
        let textured: BrailleMapDrawing.Statistics
    }
}

extension BrailleMapCapture.Scene: Encodable {}
extension BrailleMapCapture.Scene.Crop: Encodable {}
