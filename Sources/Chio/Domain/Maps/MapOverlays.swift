/// Bounded annotations with independent marker and route identity namespaces.
public struct MapOverlays {
    public let markers: [MapMarker]
    public let routes: [MapRoute]

    public static let empty = MapOverlays()

    /// At most 256 markers, 64 routes and 200,000 route vertices are accepted.
    /// Marker IDs and route IDs must each be unique within their collection.
    public init(markers: [MapMarker] = [], routes: [MapRoute] = []) throws {
        guard markers.count <= MapLimits.markers, routes.count <= MapLimits.routes,
              routes.reduce(0, { $0 + $1.path.coordinates.count }) <= MapLimits.sourceVertices
        else { throw MapValidationError.budgetExceeded }
        guard Set(markers.map(\.id)).count == markers.count,
              Set(routes.map(\.id)).count == routes.count
        else { throw MapValidationError.duplicateIdentity }
        self.markers = markers
        self.routes = routes
    }

    private init() {
        self.markers = []
        self.routes = []
    }
}

extension MapOverlays: Hashable {}
extension MapOverlays: Sendable {}
extension MapOverlays: Codable {
    private enum CodingKeys: String, CodingKey { case markers, routes }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var markerValues = try values.nestedUnkeyedContainer(forKey: .markers)
        var markers: [MapMarker] = []
        while !markerValues.isAtEnd {
            guard markers.count < MapLimits.markers else { throw MapValidationError.budgetExceeded }
            markers.append(try markerValues.decode(MapMarker.self))
        }
        var routeValues = try values.nestedUnkeyedContainer(forKey: .routes)
        var routes: [MapRoute] = []
        var vertices = 0
        while !routeValues.isAtEnd {
            guard routes.count < MapLimits.routes else { throw MapValidationError.budgetExceeded }
            let route = try routeValues.decode(MapRoute.self)
            vertices += route.path.coordinates.count
            guard vertices <= MapLimits.sourceVertices else { throw MapValidationError.budgetExceeded }
            routes.append(route)
        }
        try self.init(markers: markers, routes: routes)
    }
}
