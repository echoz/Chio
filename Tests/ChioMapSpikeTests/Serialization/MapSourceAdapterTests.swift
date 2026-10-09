@testable import ChioMapSpike
import Chio
import Foundation
import SwiftTUIRuntime
import Testing

struct MapSourceAdapterTests {
    @Test("Normalized GeoJSON preserves required source context without altering geometry")
    func normalizedInput() throws {
        let metadata = try credit("GeoJSON source")
        let coverage = try MapCoverage.boundedOfflineExtract(.init(
            southwest: MapCoordinate(latitude: -1, longitude: -1),
            northeast: MapCoordinate(latitude: 2, longitude: 2)))
        let adapter = NormalizedGeoJSONMapAdapter(metadata: metadata, coverage: coverage)
        let data = Data(geoJSON.utf8)
        let source = try adapter.adapt(data)
        #expect(try source.dataset == MapDataset.decodeGeoJSON(data))
        #expect(source.metadata == metadata && source.coverage == coverage)
        #expect(data == Data(geoJSON.utf8))
        let empty = try adapter.adapt(Data(#"{"type":"FeatureCollection","features":[]}"#.utf8))
        #expect(empty.dataset.features.isEmpty)
        #expect(empty.metadata == metadata && empty.coverage == coverage)
    }

    @Test("The adapter retains normalized schema rejection, identity checks and byte limits")
    func malformedInput() throws {
        let adapter = NormalizedGeoJSONMapAdapter(metadata: try credit("Source"), coverage: .worldwide)
        for input in [
            "not JSON",
            geoJSON.replacingOccurrences(of: "LineString", with: "MultiLineString"),
            geoJSON.replacingOccurrences(of: "[0,0]", with: "[0,0,1]"),
            geoJSON.replacingOccurrences(of: "[0,0]", with: "[181,0]"),
            geoJSON.replacingOccurrences(of: #""id":"road-1","# , with: ""),
            geoJSON.replacingOccurrences(of: "primaryRoad", with: "provider-road"),
        ] {
            #expect(throws: (any Error).self) { try adapter.adapt(Data(input.utf8)) }
        }
        #expect(throws: MapValidationError.budgetExceeded) {
            try adapter.adapt(Data(repeating: 32, count: MapLimits.geoJSONBytes + 1))
        }
        let feature = try #require(adapter.adapt(Data(geoJSON.utf8)).dataset.features.first)
        // Dataset GeoJSON encoding supplies the feature schema; repeated encoded features retain IDs.
        let dataset = try MapDataset(features: [feature])
        let collection = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(dataset)) as? [String: Any])
        let encodedFeatures = try #require(collection["features"] as? [[String: Any]])
        let repeated = try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": encodedFeatures + encodedFeatures])
        #expect(throws: MapValidationError.duplicateIdentity) { try adapter.adapt(repeated) }
    }

    @Test("A typed alternate adapter supplies the same geometry and preparation contract with its own metadata")
    @MainActor
    func substitution() throws {
        let normalized = NormalizedGeoJSONMapAdapter(metadata: try credit("GeoJSON source"), coverage: .worldwide)
        let alternate = RoadCoordinateAdapter(metadata: try credit("Survey source"))
        let coordinates = try [MapCoordinate(latitude: 0, longitude: 0), MapCoordinate(latitude: 1, longitude: 1)]
        let geoJSONSource = try adapt(normalized, input: Data(geoJSON.utf8))
        let surveySource = try adapt(alternate, input: coordinates)
        #expect(geoJSONSource.dataset == surveySource.dataset)
        #expect(geoJSONSource.metadata != surveySource.metadata)
        #expect(geoJSONSource.metadata.attribution == "GeoJSON source")
        #expect(surveySource.metadata.attribution == "Survey source")
        let camera = try MapCamera(center: MapCoordinate(latitude: 0.5, longitude: 0.5), longitudeSpan: 4)
        let viewport = try MapViewport(columns: 60, rows: 20)
        let original = try MapPreparation.prepare(dataset: geoJSONSource.dataset, camera: camera, viewport: viewport)
        let replacement = try MapPreparation.prepare(dataset: surveySource.dataset, camera: camera, viewport: viewport)
        #expect(original == replacement)
        #expect(!replacement.lines.isEmpty && !replacement.labels.isEmpty)
        let theme = ChioTheme.default
        func raster(_ map: PreparedMap) -> RasterSurface {
            let view = MapCanvasView(map: map, viewport: viewport, theme: theme, fills: true, labels: true,
                                     waterColor: theme.colors.selectedSurface,
                                     parkColor: theme.colors.selectedSurface).chioTheme(theme)
            return DefaultRenderer().render(view, proposal: .init(width: viewport.columns, height: viewport.rows),
                                            frameInstant: .zero).rasterSurface
        }
        let originalRaster = raster(original)
        #expect(originalRaster == raster(replacement))
        #expect(originalRaster.lines.joined().contains("Main Road"))
        #expect(coordinates.count == 2 && coordinates[0].longitude == 0)
    }

    private func adapt<Adapter: MapSourceAdapter>(_ adapter: Adapter, input: Adapter.Input) throws -> MapSource {
        try adapter.adapt(input)
    }

    private func credit(_ attribution: String) throws -> MapSourceMetadata {
        let url = try #require(URL(string: "https://example.test/source"))
        return try MapSourceMetadata(attribution: attribution, license: "Test license", licenseURL: url,
                                     sourceURL: url, sourceRevision: "snapshot-1")
    }

    private struct RoadCoordinateAdapter: MapSourceAdapter {
        let metadata: MapSourceMetadata

        func adapt(_ input: [MapCoordinate]) throws -> MapSource {
            let feature = try MapFeature(id: "road-1", kind: .primaryRoad, name: "Main Road",
                                         geometry: .polyline(MapPolyline(coordinates: input)))
            return try MapSource(dataset: MapDataset(features: [feature]), metadata: metadata, coverage: .worldwide)
        }
    }

    private let geoJSON = #"{"type":"FeatureCollection","features":[{"type":"Feature","id":"road-1","properties":{"kind":"primaryRoad","name":"Main Road"},"geometry":{"type":"LineString","coordinates":[[0,0],[1,1]]}}]}"#
}
