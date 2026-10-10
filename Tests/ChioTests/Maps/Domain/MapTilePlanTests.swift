@testable import Chio
import Foundation
import Testing

struct MapTilePlanTests {
    @Test("Drawable fitting shares credits, caps, compact thresholds and physical world letterboxing")
    func allocation() throws {
        let world = try camera(span: 360)
        let street = try camera(span: 0.03)
        #expect(MapViewport.fitting(width: 100, height: 40, cellAspectRatio: 2, camera: world)
                == (try MapViewport(columns: 76, rows: 38)))
        #expect(MapViewport.fitting(width: 1_000, height: 1_000, cellAspectRatio: 4, camera: world)
                == (try MapViewport(columns: 240, rows: 100, cellAspectRatio: 4)))
        #expect(MapViewport.fitting(width: 1_000, height: 1_000, cellAspectRatio: .nan, camera: street)
                == (try MapViewport(columns: 240, rows: 100)))
        #expect(MapViewport.fitting(width: 58, height: 18, cellAspectRatio: 2, camera: street) != nil)
        #expect(MapViewport.fitting(width: 57, height: 18, cellAspectRatio: 2, camera: street) == nil)
        #expect(MapViewport.fitting(width: 58, height: 17, cellAspectRatio: 2, camera: street) == nil)
        #expect(MapViewport.fitting(width: 32, height: 18, cellAspectRatio: 2, camera: try camera(span: 60)) != nil)
        #expect(MapViewport.fitting(width: 31, height: 18, cellAspectRatio: 2, camera: try camera(span: 60)) == nil)
        #expect(MapViewport.fitting(width: .min, height: .min, cellAspectRatio: .infinity, camera: street) == nil)
        let encoded = try JSONEncoder().encode(MapViewport(columns: 58, rows: 16))
        #expect(try JSONDecoder().decode(MapViewport.self, from: encoded) == (try MapViewport(columns: 58, rows: 16)))
        #expect(throws: MapValidationError.invalidViewport) {
            try JSONDecoder().decode(MapViewport.self, from: Data(#"{"columns":241,"rows":16,"cellAspectRatio":2}"#.utf8))
        }
    }

    @Test("XYZ footprints use half-open boundaries and physical height without centre-only coverage")
    func boundaries() throws {
        // Exact z2 tile column 2, and rows 1/2: horizontal edges 0 and 90 degrees.
        let request = try request(longitude: 45, span: 90, columns: 100, rows: 50, aspect: 2)
        #expect(try MapTilePlan(request: request, zoom: 2).tiles == [tile(2, 2, 1), tile(2, 2, 2)])
        // Inverse projection of 45 Mercator degrees puts the vertical edges at
        // exact z2 boundaries. Numerical roundoff must not acquire another row.
        let northTile = try self.request(latitude: MapViewport.latitude(mercatorY: 45),
                                         longitude: 45, span: 90, columns: 100, rows: 50, aspect: 2)
        #expect(try MapTilePlan(request: northTile, zoom: 2).tiles == [tile(2, 2, 1)])
        let seam = try self.request(longitude: 0, span: 0.01, columns: 100, rows: 50, aspect: 2)
        #expect(try MapTilePlan(request: seam, zoom: 2).tiles
                == [tile(2, 1, 1), tile(2, 1, 2), tile(2, 2, 1), tile(2, 2, 2)])
        let shorter = try self.request(longitude: 45, span: 90, columns: 100, rows: 10, aspect: 0.5)
        #expect(try MapTilePlan(request: shorter, zoom: 2).tiles.count == 2)
        let taller = try self.request(longitude: 45, span: 90, columns: 100, rows: 100, aspect: 4)
        #expect(try MapTilePlan(request: taller, zoom: 2).tiles.count == 4)
    }

    @Test("Dateline plans wrap and world plans contain unique addresses with polar Y clamping")
    func wrappingAndPoles() throws {
        let crossing = try request(longitude: 179, span: 4)
        #expect(try MapTilePlan(request: crossing, zoom: 2).tiles
                == [tile(2, 0, 1), tile(2, 0, 2), tile(2, 3, 1), tile(2, 3, 2)])
        let world = try request(longitude: 170, span: 360, columns: 100, rows: 100, aspect: 2)
        let plan = try MapTilePlan(request: world, zoom: 2)
        #expect(plan.tiles.count == 16 && Set(plan.tiles).count == 16)
        let first = try tile(2, 0, 0), last = try tile(2, 3, 3)
        #expect(plan.tiles.first == first && plan.tiles.last == last)
        for latitude in [-MapLimits.mercatorLatitude, MapLimits.mercatorLatitude] {
            let pole = try request(latitude: latitude, longitude: 45, span: 1)
            let poleTiles = try MapTilePlan(request: pole, zoom: 2).tiles
            let expected = try tile(2, 2, latitude > 0 ? 0 : 3)
            #expect(poleTiles == [expected])
        }
        #expect(throws: MapValidationError.tileLimitExceeded) { try MapTilePlan(request: world, zoom: 22) }
        #expect(throws: MapTileCoordinate.ValidationError.invalidAddress) { try MapTilePlan(request: world, zoom: -1) }
    }

    @Test("Desired source zoom follows terminal resolution and clamps independently of presentation")
    func zoom() throws {
        let request = try request(span: 0.03, columns: 96)
        #expect(MapTilePlan.desiredZoom(for: request, range: 2...14) == 14)
        #expect(MapTilePlan.desiredZoom(for: request, range: 2...22) == 14)
        #expect(MapTilePlan.desiredZoom(for: try self.request(span: 360), range: 2...14) == 2)
        #expect(MapTilePlan.desiredZoom(for: try self.request(span: 0.0001, columns: 240), range: 2...14) == 14)
        #expect(MapTilePlan.desiredZoom(for: try self.request(span: 0.0001, columns: 240), range: 0...22) == 22)
        #expect(try JSONDecoder().decode(MapTileRequest.self, from: JSONEncoder().encode(request)) == request)
    }

    private func camera(span: Double) throws -> MapCamera {
        try .init(center: .init(latitude: 0, longitude: 0), longitudeSpan: span)
    }

    private func request(latitude: Double = 0, longitude: Double = 0, span: Double,
                         columns: Int = 100, rows: Int = 50, aspect: Double = 2) throws -> MapTileRequest {
        try .init(camera: .init(center: .init(latitude: latitude, longitude: longitude), longitudeSpan: span),
                  viewport: .init(columns: columns, rows: rows, cellAspectRatio: aspect))
    }

    private func tile(_ zoom: Int, _ x: Int, _ y: Int) throws -> MapTileCoordinate {
        try .init(zoom: zoom, x: x, y: y)
    }
}
