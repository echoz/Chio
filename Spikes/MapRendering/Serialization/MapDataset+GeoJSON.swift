import Foundation

/// Strictly bounded two-dimensional GeoJSON subset; multi-geometries are flattened offline.
extension MapDataset: Codable {
    private enum CodingKeys: String, CodingKey { case type, features }

    static func decodeGeoJSON(_ data: Data) throws -> Self {
        guard data.count <= MapLimits.geoJSONBytes else { throw MapValidationError.budgetExceeded }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(String.self, forKey: .type) == "FeatureCollection" else {
            throw MapValidationError.unsupportedGeoJSON
        }
        var source = try values.nestedUnkeyedContainer(forKey: .features)
        var features: [MapFeature] = []
        var vertices = 0
        while !source.isAtEnd {
            guard features.count < MapLimits.features else { throw MapValidationError.budgetExceeded }
            let feature = try source.decode(GeoJSONFeature.self).feature
            vertices += feature.geometry.vertexCount
            guard vertices <= MapLimits.sourceVertices else { throw MapValidationError.budgetExceeded }
            features.append(feature)
        }
        try self.init(features: features)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode("FeatureCollection", forKey: .type)
        var target = values.nestedUnkeyedContainer(forKey: .features)
        for feature in features { try target.encode(GeoJSONFeature(feature: feature)) }
    }
}

private struct GeoJSONFeature: Codable {
    let feature: MapFeature
    private enum CodingKeys: String, CodingKey { case type, id, properties, geometry }
    private enum PropertyKeys: String, CodingKey { case kind, name }

    init(feature: MapFeature) { self.feature = feature }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(String.self, forKey: .type) == "Feature" else {
            throw MapValidationError.unsupportedGeoJSON
        }
        let properties = try values.nestedContainer(keyedBy: PropertyKeys.self, forKey: .properties)
        feature = try MapFeature(id: values.decode(String.self, forKey: .id),
                                 kind: properties.decode(MapFeature.Kind.self, forKey: .kind),
                                 name: properties.decodeIfPresent(String.self, forKey: .name) ?? "",
                                 geometry: values.decode(GeoJSONGeometry.self, forKey: .geometry).geometry)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode("Feature", forKey: .type)
        try values.encode(feature.id, forKey: .id)
        var properties = values.nestedContainer(keyedBy: PropertyKeys.self, forKey: .properties)
        try properties.encode(feature.kind, forKey: .kind)
        try properties.encode(feature.name, forKey: .name)
        try values.encode(GeoJSONGeometry(geometry: feature.geometry), forKey: .geometry)
    }
}

private struct GeoJSONGeometry: Codable {
    let geometry: MapGeometry
    private enum CodingKeys: String, CodingKey { case type, coordinates }

    init(geometry: MapGeometry) { self.geometry = geometry }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "LineString":
            geometry = try .polyline(MapPolyline(coordinates: Self.path(from: values.superDecoder(forKey: .coordinates))))
        case "Polygon":
            var source = try values.nestedUnkeyedContainer(forKey: .coordinates)
            var rings: [MapRing] = []
            var vertices = 0
            while !source.isAtEnd {
                guard rings.count < MapLimits.polygonRings else { throw MapValidationError.budgetExceeded }
                let ring = try MapRing(coordinates: Self.path(from: source.superDecoder()))
                vertices += ring.coordinates.count
                guard vertices <= MapLimits.pathVertices else { throw MapValidationError.budgetExceeded }
                rings.append(ring)
            }
            geometry = try .polygon(MapPolygon(rings: rings))
        default:
            throw MapValidationError.unsupportedGeoJSON
        }
    }

    private static func path(from decoder: any Decoder) throws -> [MapCoordinate] {
        var source = try decoder.unkeyedContainer()
        var coordinates: [MapCoordinate] = []
        while !source.isAtEnd {
            guard coordinates.count < MapLimits.pathVertices else { throw MapValidationError.budgetExceeded }
            var pair = try source.nestedUnkeyedContainer()
            let longitude = try pair.decode(Double.self)
            let latitude = try pair.decode(Double.self)
            guard pair.isAtEnd else { throw MapValidationError.unsupportedGeoJSON }
            coordinates.append(try MapCoordinate(latitude: latitude, longitude: longitude))
        }
        return coordinates
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch geometry {
        case .polyline(let line):
            try values.encode("LineString", forKey: .type)
            try values.encode(Self.pairs(line.coordinates), forKey: .coordinates)
        case .polygon(let polygon):
            try values.encode("Polygon", forKey: .type)
            try values.encode(polygon.rings.map { Self.pairs($0.coordinates) }, forKey: .coordinates)
        }
    }

    private static func pairs(_ coordinates: [MapCoordinate]) -> [[Double]] {
        coordinates.map { [$0.longitude, $0.latitude] }
    }
}
