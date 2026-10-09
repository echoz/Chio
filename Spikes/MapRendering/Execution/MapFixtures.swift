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
        var next: Self { self == .overpass ? .openfreemap : .overpass }
    }

    enum Scene: String {
        case world, street

        var title: String { self == .world ? "World" : "Singapore · Marina Bay" }
        var next: Self { self == .world ? .street : .world }
        var camera: MapCamera {
            // Fixed experiment inputs satisfy the checked geographic constructors.
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
