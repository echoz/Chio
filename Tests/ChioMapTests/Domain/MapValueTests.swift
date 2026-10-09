@testable import ChioMaps
@testable import Chio
import Foundation
import Testing

struct MapValueTests {
    @Test("Coordinates reject nonfinite and out-of-range values through creation and decoding")
    func coordinateValidation() throws {
        for latitude in [Double.nan, .infinity, -91, 91] {
            #expect(throws: MapValidationError.invalidCoordinate) {
                try MapCoordinate(latitude: latitude, longitude: 0)
            }
        }
        #expect(throws: MapValidationError.invalidCoordinate) { try MapCoordinate(latitude: 0, longitude: 181) }
        #expect(throws: MapValidationError.invalidCoordinate) {
            try JSONDecoder().decode(MapCoordinate.self, from: Data(#"{"latitude":91,"longitude":0}"#.utf8))
        }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Inf", negativeInfinity: "-Inf", nan: "NaN")
        #expect(throws: MapValidationError.invalidCoordinate) {
            try decoder.decode(MapCoordinate.self, from: Data(#"{"latitude":"NaN","longitude":0}"#.utf8))
        }
        let coordinate = try MapCoordinate(latitude: 90, longitude: -180)
        #expect(try JSONDecoder().decode(MapCoordinate.self, from: JSONEncoder().encode(coordinate)) == coordinate)
    }

    @Test("Camera initialization rejects projection poles and unbounded scale, including Codable")
    func cameraValidation() throws {
        let zero = try MapCoordinate(latitude: 0, longitude: 0)
        for span in [0.0, -1, .infinity, 361, MapLimits.minimumLongitudeSpan / 2] {
            #expect(throws: MapValidationError.invalidCamera) { try MapCamera(center: zero, longitudeSpan: span) }
        }
        #expect(throws: MapValidationError.invalidCamera) {
            try MapCamera(center: MapCoordinate(latitude: 90, longitude: 0), longitudeSpan: 360)
        }
        #expect(throws: MapValidationError.invalidCamera) {
            try JSONDecoder().decode(MapCamera.self, from: Data(#"{"center":{"latitude":90,"longitude":0},"longitudeSpan":360}"#.utf8))
        }
    }

    @Test("Camera replacements preserve center/scale contracts and original values")
    func cameraReplacements() throws {
        let camera = try MapCamera(center: MapCoordinate(latitude: 0, longitude: 179), longitudeSpan: 20)
        let moved = try camera.panned(longitudeFraction: 0.2, latitudeFraction: 100)
        #expect(abs(moved.center.longitude - -177) < 1e-9)
        #expect(abs(moved.center.latitude - MapLimits.mercatorLatitude) < 1e-9)
        #expect(try camera.zoomed(by: 1_000_000).longitudeSpan == MapLimits.minimumLongitudeSpan)
        #expect(try camera.zoomed(by: 0.000001).longitudeSpan == 360)
        #expect(camera.center.longitude == 179 && camera.center.latitude == 0 && camera.longitudeSpan == 20)
        #expect(throws: MapValidationError.invalidCamera) { try camera.zoomed(by: .nan) }
        #expect(throws: MapValidationError.invalidCamera) { try camera.panned(longitudeFraction: .infinity, latitudeFraction: 0) }
        let north = try camera.panned(longitudeFraction: 0, latitudeFraction: 1)
        // Inverse Mercator at y=20 degrees is 19.605793951272645 degrees latitude.
        #expect(abs(north.center.latitude - 19.605793951272645) < 1e-9)
    }

    @Test("Rings require closure, three distinct non-collinear points, and bounded paths")
    func ringValidation() throws {
        let a = try MapCoordinate(latitude: 0, longitude: 0)
        let b = try MapCoordinate(latitude: 0, longitude: 1)
        let c = try MapCoordinate(latitude: 1, longitude: 1)
        #expect(throws: MapValidationError.invalidRing) { try MapRing(coordinates: [a, b, c]) }
        #expect(throws: MapValidationError.invalidRing) { try MapRing(coordinates: [a, b, a, a]) }
        #expect(throws: MapValidationError.invalidRing) {
            try MapRing(coordinates: [a, b, MapCoordinate(latitude: 0, longitude: 2), a])
        }
        #expect(throws: MapValidationError.budgetExceeded) {
            try MapPolyline(coordinates: Array(repeating: a, count: MapLimits.pathVertices + 1))
        }
        #expect(throws: MapValidationError.invalidRing) {
            try JSONDecoder().decode(MapRing.self, from: Data(#"{"coordinates":[{"latitude":0,"longitude":0},{"latitude":0,"longitude":1},{"latitude":1,"longitude":1}]}"#.utf8))
        }
        let ring = try MapRing(coordinates: [a, b, c, a])
        #expect(try JSONDecoder().decode(MapRing.self, from: JSONEncoder().encode(ring)) == ring)
        #expect(throws: MapValidationError.invalidRing) { try MapPolygon(rings: []) }
    }

    @Test("Viewport rejects invalid metrics and oversized terminal allocations during decoding")
    func viewportValidation() throws {
        for aspect in [0.0, .nan, .infinity, 4.1] {
            #expect(throws: MapValidationError.invalidViewport) { try MapViewport(columns: 100, rows: 30, cellAspectRatio: aspect) }
        }
        #expect(throws: MapValidationError.invalidViewport) { try MapViewport(columns: 241, rows: 30) }
        #expect(throws: MapValidationError.invalidViewport) { try MapViewport(columns: 100, rows: 101) }
        #expect(throws: MapValidationError.invalidViewport) {
            try JSONDecoder().decode(MapViewport.self, from: Data(#"{"columns":241,"rows":30,"cellAspectRatio":2}"#.utf8))
        }
        let viewport = try MapViewport(columns: 100, rows: 30)
        #expect(viewport.cellAspectRatio == 2)
        #expect(try JSONDecoder().decode(MapViewport.self, from: JSONEncoder().encode(viewport)) == viewport)
    }
}
