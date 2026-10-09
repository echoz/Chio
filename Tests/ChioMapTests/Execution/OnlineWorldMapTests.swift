@testable import Chio
@testable import ChioMaps
import Foundation
import SwiftTUIRuntime
import Synchronization
import Testing

@MainActor
struct OnlineWorldMapTests {
    @Test("Four genuine zoom-one tiles cover the world without substituting bundled geography")
    func completeWorld() async throws {
        let entries = try worldEntries()
        let metadata = try MapFixtures.load().openFreeMapSource.metadata
        // Counts were independently decoded from the original integer MVT commands.
        let expected = [(12, 1_903), (2, 588), (12, 1_683), (4, 1_016)]
        for (index, entry) in entries.enumerated() {
            let source = try OpenMapTilesAdapter(tile: entry.0, metadata: metadata).adapt(entry.1)
            #expect(source.dataset.features.count == expected[index].0)
            #expect(source.dataset.vertexCount == expected[index].1)
        }
        let bytes = Dictionary(uniqueKeysWithValues: entries)
        let calls = Mutex<[String]>([])
        let source = try OpenMapTilesSource(template: "https://example.test/{z}/{x}/{y}.pbf",
                                            zoomRange: 0...14, metadata: metadata)
        let loader = MapTileLoader(source: source, transport: { url, _ in
            calls.withLock { $0.append(url.path) }
            let parts = url.deletingPathExtension().pathComponents
            let tile = try MapTileCoordinate(zoom: Int(parts[1])!, x: Int(parts[2])!, y: Int(parts[3])!)
            guard let data = bytes[tile] else { throw MapTileLoader.LoadingError.httpStatus(404) }
            return MapHTTPClient.Response(data: data, headers: ["cache-control": "max-age=60"])
        })
        let viewport = try MapViewport(columns: 98, rows: 48)
        for longitude in [0.0, 179.0, -179.0] {
            let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: longitude), longitudeSpan: 360)
            let request = MapTileRequest(camera: camera, viewport: viewport)
            let snapshot = try await loader.load(request)
            #expect(snapshot.request == request)
            #expect(snapshot.requestedZoom == 1 && snapshot.attainedZoom == 1)
            #expect(snapshot.source.metadata == metadata)
            #expect(snapshot.source.dataset.features.count == 30)
            #expect(snapshot.source.dataset.vertexCount == 5_190)
            guard case .tiled(let coverage) = snapshot.source.coverage else {
                Issue.record("Online world must retain acquired tile coverage"); return
            }
            #expect(Set(coverage.tiles) == Set(entries.map { $0.0 }))
            #expect(coverage.covers(request))
        }
        #expect(calls.withLock { $0.count } == 4)
        #expect(calls.withLock { Set($0) } == ["/1/0/0.pbf", "/1/0/1.pbf", "/1/1/0.pbf", "/1/1/1.pbf"])
    }

    @Test("Online world land and oceans remain recognizable across detail, themes, narrow layouts and seam pans")
    func worldRaster() throws {
        let metadata = try MapFixtures.load().openFreeMapSource.metadata
        let features = try worldEntries().flatMap {
            try OpenMapTilesAdapter(tile: $0.0, metadata: metadata).adapt($0.1).dataset.features
        }
        let dataset = try MapDataset(features: features)
        // These inland/ocean locations establish geography independently of the
        // adapter's own output counts and avoid testing coastline precision.
        let samples: [(Double, Double, Bool)] = [
            (-100, 40, false), (15, 25, false), (135, -25, false),
            (-130, 0, true), (-30, 0, true), (80, -30, true),
        ]
        for (columns, rows) in [(98, 48), (40, 20)] {
            let viewport = try MapViewport(columns: columns, rows: rows)
            for longitude in [0.0, 179.0] {
                let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: longitude), longitudeSpan: 360)
                for detail in MapDetail.allCases {
                    let prepared = try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport, detail: detail)
                    for theme in [ChioTheme.default, .light, .btop] {
                        let view = try MapCanvasView(map: prepared, viewport: viewport, theme: theme,
                            fills: true, labels: false, waterColor: theme.map.water, parkColor: theme.map.park, detail: detail).chioTheme(theme)
                        let surface = DefaultRenderer().render(view,
                            proposal: ProposedSize(width: columns, height: rows), frameInstant: .zero).rasterSurface
                        for (sampleLongitude, latitude, isWater) in samples {
                            let point = viewport.project(try MapCoordinate(latitude: latitude, longitude: sampleLongitude), camera: camera)
                            let cell = surface.cells[Int(point.y)][Int(point.x)]
                            let expectedColor = isWater ? theme.map.water : theme.colors.surface
                            #expect(cell.style?.backgroundColor == expectedColor,
                                "Location \(sampleLongitude),\(latitude); \(columns)x\(rows), center \(longitude), detail \(detail)")
                        }
                    }
                }
            }
        }
    }

    private func worldEntries() throws -> [(MapTileCoordinate, Data)] {
        try [(0, 0), (0, 1), (1, 0), (1, 1)].map { x, y in
            let url = try #require(Bundle.module.url(forResource: "1-\(x)-\(y)", withExtension: "pbf",
                                                     subdirectory: "Fixtures/OnlineTiles"))
            return (try MapTileCoordinate(zoom: 1, x: x, y: y), try Data(contentsOf: url))
        }
    }
}
