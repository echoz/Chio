import Foundation

/// Terminal allocation and physical cell height/width. Estimated metrics use 2.
struct MapViewport {
    let columns: Int
    let rows: Int
    let cellAspectRatio: Double

    init(columns: Int, rows: Int, cellAspectRatio: Double = 2) throws {
        guard (1...MapLimits.columns).contains(columns), (1...MapLimits.rows).contains(rows),
              cellAspectRatio.isFinite, (0.5...4).contains(cellAspectRatio)
        else { throw MapValidationError.invalidViewport }
        self.columns = columns
        self.rows = rows
        self.cellAspectRatio = cellAspectRatio
    }

    /// Returns a finite point in cell units; outside points are useful for culling.
    func project(_ coordinate: MapCoordinate, camera: MapCamera) -> PreparedMap.Point {
        let longitude = Self.unwrap(coordinate.longitude, near: camera.center.longitude)
        return point(longitude: longitude, mercatorY: Self.mercatorY(coordinate.latitude), camera: camera)
    }

    func point(longitude: Double, mercatorY: Double, camera: MapCamera) -> PreparedMap.Point {
        let cellsPerDegree = Double(columns) / camera.longitudeSpan
        return .init(x: Double(columns) / 2 + (longitude - camera.center.longitude) * cellsPerDegree,
                     y: Double(rows) / 2 - (mercatorY - Self.mercatorY(camera.center.latitude))
                        * cellsPerDegree / cellAspectRatio)
    }

    static func mercatorY(_ latitude: Double) -> Double {
        // Source poles clamp explicitly; the camera itself must already be in-domain.
        let clamped = min(MapLimits.mercatorLatitude, max(-MapLimits.mercatorLatitude, latitude))
        return log(tan(.pi / 4 + clamped * .pi / 360)) * 180 / .pi
    }

    static func latitude(mercatorY: Double) -> Double {
        min(MapLimits.mercatorLatitude,
            max(-MapLimits.mercatorLatitude, (2 * atan(exp(mercatorY * .pi / 180)) - .pi / 2) * 180 / .pi))
    }

    static func unwrap(_ longitude: Double, near reference: Double) -> Double {
        longitude + ((reference - longitude) / 360).rounded() * 360
    }
}

extension MapViewport: Hashable {}
extension MapViewport: Sendable {}
extension MapViewport: Codable {
    private enum CodingKeys: String, CodingKey { case columns, rows, cellAspectRatio }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(columns: values.decode(Int.self, forKey: .columns),
                      rows: values.decode(Int.self, forKey: .rows),
                      cellAspectRatio: values.decode(Double.self, forKey: .cellAspectRatio))
    }
}
