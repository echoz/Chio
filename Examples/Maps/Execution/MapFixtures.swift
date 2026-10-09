import Chio
import Foundation
import SwiftTUI

/// Bundled data is loaded once at the executable boundary, never by a view or value transform.
struct MapFixtures {
    let worldSource: MapSource
    let streetSource: MapSource
    let openFreeMapSource: MapSource

    var world: MapDataset { worldSource.dataset }
    var street: MapDataset { streetSource.dataset }

    static func load() throws -> Self {
        func read(_ name: String, extension fileExtension: String) throws -> Data {
            guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try Data(contentsOf: url)
        }
        let manifest = try JSONDecoder().decode(MapFixtureManifest.self, from: read("provenance", extension: "json"))
        let worldAdapter = NormalizedGeoJSONMapAdapter(metadata: manifest.worldMetadata, coverage: .worldwide)
        let streetAdapter = NormalizedGeoJSONMapAdapter(metadata: manifest.streetMetadata,
                                                      coverage: .boundedOfflineExtract(manifest.streetBounds))
        let tileAdapter = OpenMapTilesAdapter(tile: manifest.openFreeMapTile, metadata: manifest.openFreeMapMetadata)
        return try Self(worldSource: worldAdapter.adapt(read("world", extension: "geojson")),
                        streetSource: streetAdapter.adapt(read("singapore", extension: "geojson")),
                        openFreeMapSource: tileAdapter.adapt(read("openfreemap-singapore", extension: "pbf")))
    }

    func source(for scene: Scene, streetSource choice: StreetSource = .overpass) -> MapSource {
        scene == .world ? worldSource : choice == .overpass ? streetSource : openFreeMapSource
    }
    func dataset(for scene: Scene, streetSource choice: StreetSource = .overpass) -> MapDataset {
        source(for: scene, streetSource: choice).dataset
    }

    enum StreetSource: String {
        case overpass, openfreemap
        var title: String { self == .overpass ? "Overpass" : "OpenFreeMap" }
    }

    enum Scene: String {
        case world, street

        var title: String { self == .world ? "World" : "Singapore · Marina Bay" }
        var next: Self { self == .world ? .street : .world }
        /// Demonstration locations and synthetic guides, independent of source geography.
        var overlays: MapOverlays {
            // These fixed fixtures exercise the same checked API as application input.
            try! makeOverlays()
        }

        private func makeOverlays() throws -> MapOverlays {
            let markers: [MapMarker]
            switch self {
            case .world:
                markers = try [
                    MapMarker(id: "london", coordinate: MapCoordinate(latitude: 51.5074, longitude: -0.1278),
                              title: "London"),
                    MapMarker(id: "singapore", coordinate: MapCoordinate(latitude: 1.3521, longitude: 103.8198),
                              title: "Singapore"),
                    MapMarker(id: "sydney", coordinate: MapCoordinate(latitude: -33.8688, longitude: 151.2093),
                              title: "Sydney")
                ]
            case .street:
                markers = try [
                    MapMarker(id: "merlion", coordinate: MapCoordinate(latitude: 1.2868, longitude: 103.8545),
                              title: "Merlion"),
                    MapMarker(id: "gardens", coordinate: MapCoordinate(latitude: 1.2816, longitude: 103.8636),
                              title: "Gardens by the Bay"),
                    MapMarker(id: "flyer", coordinate: MapCoordinate(latitude: 1.2893, longitude: 103.8634),
                              title: "Singapore Flyer")
                ]
            }
            let route = try MapRoute(id: "synthetic-guide", title: "Synthetic guide",
                                     path: MapPolyline(coordinates: markers.map(\.coordinate)))
            return try MapOverlays(markers: markers, routes: [route])
        }

        var camera: MapCamera {
            // Fixed example inputs satisfy the checked geographic constructors.
            switch self {
            case .world: try! MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 360)
            case .street: try! MapCamera(center: MapCoordinate(latitude: 1.289, longitude: 103.866), longitudeSpan: 0.030)
            }
        }
    }
}

extension MapFixtures: Sendable {}
extension MapFixtures.Scene: CaseIterable {}
extension MapFixtures.Scene: Hashable {}
extension MapFixtures.Scene: Codable {}
extension MapFixtures.Scene: Sendable {}
extension MapFixtures.Scene: ExpressibleByArgument {}
extension MapFixtures.StreetSource: CaseIterable {}
extension MapFixtures.StreetSource: Hashable {}
extension MapFixtures.StreetSource: Codable {}
extension MapFixtures.StreetSource: Sendable {}
extension MapFixtures.StreetSource: ExpressibleByArgument {}
