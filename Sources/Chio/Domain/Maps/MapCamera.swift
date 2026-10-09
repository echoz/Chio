import Foundation

/// North-up Web Mercator camera; the longitude span is the sole scale value.
public struct MapCamera {
    public let center: MapCoordinate
    public let longitudeSpan: Double

    public init(center: MapCoordinate, longitudeSpan: Double) throws {
        guard abs(center.latitude) <= MapLimits.mercatorLatitude,
              longitudeSpan.isFinite,
              (MapLimits.minimumLongitudeSpan...360).contains(longitudeSpan)
        else { throw MapValidationError.invalidCamera }
        self.center = center
        self.longitudeSpan = longitudeSpan
    }

    /// Fractions refer to the longitude span in Mercator degrees; positive y moves north.
    public func panned(longitudeFraction: Double, latitudeFraction: Double) throws -> Self {
        guard longitudeFraction.isFinite, latitudeFraction.isFinite else {
            throw MapValidationError.invalidCamera
        }
        let longitude = center.longitude + longitudeSpan * longitudeFraction
        let y = MapViewport.mercatorY(center.latitude) + longitudeSpan * latitudeFraction
        guard longitude.isFinite, y.isFinite else { throw MapValidationError.invalidCamera }
        let wrapped = (longitude + 180).truncatingRemainder(dividingBy: 360)
        let latitude = MapViewport.latitude(mercatorY: min(180, max(-180, y)))
        return try Self(center: MapCoordinate(latitude: latitude,
                                             longitude: (wrapped < 0 ? wrapped + 360 : wrapped) - 180),
                        longitudeSpan: longitudeSpan)
    }

    /// A factor above one zooms in while keeping the center fixed.
    public func zoomed(by factor: Double) throws -> Self {
        guard factor.isFinite, factor > 0 else { throw MapValidationError.invalidCamera }
        return try Self(center: center,
                        longitudeSpan: min(360, max(MapLimits.minimumLongitudeSpan, longitudeSpan / factor)))
    }
}

extension MapCamera: Hashable {}
extension MapCamera: Sendable {}
extension MapCamera: Codable {
    private enum CodingKeys: String, CodingKey { case center, longitudeSpan }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(center: values.decode(MapCoordinate.self, forKey: .center),
                      longitudeSpan: values.decode(Double.self, forKey: .longitudeSpan))
    }
}
