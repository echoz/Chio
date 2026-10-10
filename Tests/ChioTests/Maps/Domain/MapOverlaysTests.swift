import Chio
import Foundation
import Testing

struct MapOverlaysTests {
    @Test("Overlay values retain authored text, geometry and independent identity namespaces")
    func valuesAndCoding() throws {
        let coordinate = try MapCoordinate(latitude: 1, longitude: 103)
        let path = try path()
        let marker = try MapMarker(id: "shared", coordinate: coordinate)
        let route = try MapRoute(id: "shared", title: "  Walk 界  ", path: path)
        let overlays = try MapOverlays(markers: [marker], routes: [route])
        #expect(marker.coordinate == coordinate)
        #expect(marker.title.isEmpty)
        #expect(route.title == "  Walk 界  ")
        #expect(route.path == path)
        #expect(try MapRoute(id: "untitled", path: path).title.isEmpty)
        #expect(try MapOverlays() == .empty)
        #expect(try JSONDecoder().decode(MapOverlays.self, from: JSONEncoder().encode(overlays)) == overlays)
        let encodedMarker = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(marker)) as? [String: Any])
        #expect(encodedMarker["title"] as? String == "")
    }

    @Test("Markers and routes check identities and title bytes in construction and decoding")
    func textValidation() throws {
        let coordinate = try MapCoordinate(latitude: 1, longitude: 103)
        let path = try path()
        for id in ["", "line\nbreak", "delete\u{7f}", String(repeating: "x", count: 257)] {
            #expect(throws: MapValidationError.invalidIdentity) {
                try MapMarker(id: id, coordinate: coordinate)
            }
            #expect(throws: MapValidationError.invalidIdentity) {
                try MapRoute(id: id, path: path)
            }
        }
        for title in ["line\nbreak", "delete\u{7f}", String(repeating: "界", count: 86)] {
            #expect(throws: MapValidationError.invalidIdentity) {
                try MapMarker(id: "marker", coordinate: coordinate, title: title)
            }
            #expect(throws: MapValidationError.invalidIdentity) {
                try MapRoute(id: "route", title: title, path: path)
            }
        }
        let longest = String(repeating: "x", count: 256)
        #expect(try MapMarker(id: longest, coordinate: coordinate, title: longest).title == longest)
        #expect(try MapRoute(id: longest, title: longest, path: path).id == longest)
        let invalidMarker = #"{"id":"","coordinate":{"latitude":1,"longitude":103},"title":""}"#
        #expect(throws: MapValidationError.invalidIdentity) {
            try JSONDecoder().decode(MapMarker.self, from: Data(invalidMarker.utf8))
        }
        let invalidRoute = #"{"id":"route","title":"bad\ntext","path":{"coordinates":[{"latitude":1,"longitude":103},{"latitude":2,"longitude":104}]}}"#
        #expect(throws: MapValidationError.invalidIdentity) {
            try JSONDecoder().decode(MapRoute.self, from: Data(invalidRoute.utf8))
        }
    }

    @Test("Each overlay identity collection rejects duplicates through both construction and decoding")
    func duplicateIdentities() throws {
        let marker = try MapMarker(id: "marker", coordinate: MapCoordinate(latitude: 0, longitude: 0))
        let route = try MapRoute(id: "route", path: path())
        for payload in [Payload(markers: [marker, marker], routes: []),
                        Payload(markers: [], routes: [route, route])] {
            #expect(throws: MapValidationError.duplicateIdentity) {
                try MapOverlays(markers: payload.markers, routes: payload.routes)
            }
            #expect(throws: MapValidationError.duplicateIdentity) {
                try JSONDecoder().decode(MapOverlays.self, from: JSONEncoder().encode(payload))
            }
        }
    }

    @Test("Overlay item limits accept the boundary and reject overflow through checked decoding")
    func itemBudgets() throws {
        let coordinate = try MapCoordinate(latitude: 0, longitude: 0)
        let path = try path()
        let markers = try (0..<256).map { try MapMarker(id: "m\($0)", coordinate: coordinate) }
        let routes = try (0..<64).map { try MapRoute(id: "r\($0)", path: path) }
        let boundary = try MapOverlays(markers: markers, routes: routes)
        #expect(try JSONDecoder().decode(MapOverlays.self, from: JSONEncoder().encode(boundary)) == boundary)
        let extraMarker = try MapMarker(id: "extra", coordinate: coordinate)
        let extraRoute = try MapRoute(id: "extra", path: path)
        for payload in [Payload(markers: markers + [extraMarker], routes: []),
                        Payload(markers: [], routes: routes + [extraRoute])] {
            #expect(throws: MapValidationError.budgetExceeded) {
                try MapOverlays(markers: payload.markers, routes: payload.routes)
            }
            #expect(throws: MapValidationError.budgetExceeded) {
                try JSONDecoder().decode(MapOverlays.self, from: JSONEncoder().encode(payload))
            }
        }
    }

    @Test("Route vertices share the 200,000 source budget across individually valid paths")
    func aggregateVertexBudget() throws {
        let a = try MapCoordinate(latitude: 0, longitude: 0)
        let b = try MapCoordinate(latitude: 1, longitude: 1)
        let path = try MapPolyline(coordinates: (0..<20_000).map { $0.isMultiple(of: 2) ? a : b })
        let routes = try (0..<10).map { try MapRoute(id: "r\($0)", path: path) }
        let boundary = try MapOverlays(routes: routes)
        #expect(boundary.routes.reduce(0) { $0 + $1.path.coordinates.count } == 200_000)
        let overflow = routes + [try MapRoute(id: "extra", path: path)]
        #expect(throws: MapValidationError.budgetExceeded) { try MapOverlays(routes: overflow) }
        #expect(throws: MapValidationError.budgetExceeded) {
            try JSONDecoder().decode(MapOverlays.self, from: JSONEncoder().encode(Payload(markers: [], routes: overflow)))
        }
    }

    private func path() throws -> MapPolyline {
        try MapPolyline(coordinates: [MapCoordinate(latitude: 1, longitude: 103),
                                      MapCoordinate(latitude: 2, longitude: 104)])
    }

    private struct Payload: Encodable {
        let markers: [MapMarker]
        let routes: [MapRoute]
    }
}
