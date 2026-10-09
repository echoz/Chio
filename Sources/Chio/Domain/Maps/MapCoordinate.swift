import Foundation

/// Longitude and latitude in degrees, including the geographic poles.
public struct MapCoordinate {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { throw MapValidationError.invalidCoordinate }
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension MapCoordinate: Hashable {}
extension MapCoordinate: Sendable {}
extension MapCoordinate: Codable {
    private enum CodingKeys: String, CodingKey { case latitude, longitude }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(latitude: values.decode(Double.self, forKey: .latitude),
                      longitude: values.decode(Double.self, forKey: .longitude))
    }
}
