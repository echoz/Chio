import Foundation
import SwiftTUI

/// Bundled data is loaded once at the executable boundary, never by a view or value transform.
struct MapFixtures {
    let world: MapDataset
    let street: MapDataset

    static func load() throws -> Self {
        func dataset(_ name: String) throws -> MapDataset {
            guard let url = Bundle.module.url(forResource: name, withExtension: "geojson", subdirectory: "Fixtures") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try MapDataset.decodeGeoJSON(Data(contentsOf: url))
        }
        return try Self(world: dataset("world"), street: dataset("singapore"))
    }

    func dataset(for scene: Scene) -> MapDataset { scene == .world ? world : street }

    enum Scene: String {
        case world, street

        var title: String { self == .world ? "World" : "Singapore · Marina Bay" }
        var next: Self { self == .world ? .street : .world }
        var camera: MapCamera {
            // Fixed experiment inputs satisfy the checked geographic constructors.
            switch self {
            case .world: try! MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 360)
            case .street: try! MapCamera(center: MapCoordinate(latitude: 1.289, longitude: 103.856), longitudeSpan: 0.030)
            }
        }
        var attribution: String {
            self == .world ? "Natural Earth · public domain" : "© OpenStreetMap contributors"
        }
        var license: String {
            self == .world ? "naturalearthdata.com" : "ODbL · openstreetmap.org/copyright"
        }
    }
}

extension MapFixtures: Sendable {}
extension MapFixtures.Scene: CaseIterable {}
extension MapFixtures.Scene: Hashable {}
extension MapFixtures.Scene: Codable {}
extension MapFixtures.Scene: Sendable {}
extension MapFixtures.Scene: ExpressibleByArgument {}
