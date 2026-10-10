@testable import ChioMaps
@testable import Chio
import Testing

struct MapFixturesTests {
    @Test("Scene and street choices preserve fixture identity, capture labels and cycle wrapping")
    func choicePolicies() throws {
        let fixtures = try MapFixtures.load()
        #expect(fixtures.source(for: .world, streetSource: .overpass) == fixtures.worldSource)
        #expect(fixtures.source(for: .world, streetSource: .openfreemap) == fixtures.worldSource)
        #expect(fixtures.source(for: .street, streetSource: .overpass) == fixtures.streetSource)
        #expect(fixtures.source(for: .street, streetSource: .openfreemap) == fixtures.openFreeMapSource)
        #expect(MapFixtures.Scene.world.title == "World")
        #expect(MapFixtures.Scene.street.title == "Singapore · Marina Bay")
        #expect(MapFixtures.Scene.world.next == .street)
        #expect(MapFixtures.Scene.street.next == .world)
        #expect(MapFixtures.Scene.world.sourceTitle(streetSource: .openfreemap) == "Natural Earth")
        #expect(MapFixtures.Scene.street.sourceTitle(streetSource: .overpass) == "Overpass")
        #expect(MapFixtures.Scene.street.sourceTitle(streetSource: .openfreemap) == "OpenFreeMap")
        #expect(MapFixtures.Scene.world.sourceIdentifier(streetSource: .openfreemap) == "natural-earth")
        #expect(MapFixtures.Scene.street.sourceIdentifier(streetSource: .overpass) == "overpass")
        #expect(MapFixtures.Scene.street.sourceIdentifier(streetSource: .openfreemap) == "openfreemap")
        #expect(!MapExampleAcquisition.offline.isOnline)
        #expect(MapExampleAcquisition.openFreeMap.isOnline)
    }

    @Test("Fixtures load source metadata once with explicit worldwide and neighborhood query coverage")
    func sourceContracts() throws {
        let fixtures = try MapFixtures.load()
        let world = fixtures.source(for: .world)
        let street = fixtures.source(for: .street)
        #expect(world.dataset == fixtures.world && street.dataset == fixtures.street)
        #expect(world.dataset == fixtures.dataset(for: .world))
        #expect(street.dataset == fixtures.dataset(for: .street))
        #expect(world.coverage == .worldwide)
        #expect(world.metadata.attribution == "Made with Natural Earth")
        #expect(world.metadata.license == "Public domain")
        #expect(world.metadata.sourceRevision == "693f11422f4e08d2da4566b854dda53eb7c39fb3")
        #expect(world.metadata.attributionURL == nil)
        #expect(street.metadata.attribution == "© OpenStreetMap contributors")
        #expect(street.metadata.license == "ODbL 1.0")
        #expect(street.metadata.attributionURL?.absoluteString == "https://www.openstreetmap.org/copyright")
        #expect(street.metadata.sourceRevision == "2026-10-09T03:27:04Z")
        guard case .boundedOfflineExtract(let bounds) = street.coverage else {
            Issue.record("Street coverage must be an explicitly bounded extract")
            return
        }
        #expect(bounds.southwest.latitude == 1.278 && bounds.southwest.longitude == 103.842)
        #expect(bounds.northeast.latitude == 1.300 && bounds.northeast.longitude == 103.870)
        // Complete retained ways extend outside the query. Their extent does not expand availability.
        let outside = try MapCoordinate(latitude: 1.311, longitude: 103.856)
        #expect(!street.coverage.contains(outside))
        #expect(street.dataset.features.contains { feature in
            switch feature.geometry {
            case .polyline(let line): line.coordinates.contains { $0.latitude > bounds.northeast.latitude }
            case .polygon(let polygon): polygon.rings.contains { $0.coordinates.contains { $0.latitude > bounds.northeast.latitude } }
            }
        })
    }
}
