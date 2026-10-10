/// The camera and actual drawable allocation for one tile acquisition.
/// Presentation detail is independent of provider source resolution.
public struct MapTileRequest {
    public let camera: MapCamera
    public let viewport: MapViewport

    public init(camera: MapCamera, viewport: MapViewport) {
        self.camera = camera
        self.viewport = viewport
    }

    /// Geographic membership in the requested drawing region, independent of XYZ
    /// resolution. Longitudes wrap; geography beyond Mercator is not available.
    func contains(_ coordinate: MapCoordinate) -> Bool {
        guard abs(coordinate.latitude) <= MapLimits.mercatorLatitude else { return false }
        let longitude = MapViewport.unwrap(coordinate.longitude, near: camera.center.longitude)
        guard camera.longitudeSpan == 360
                || abs(longitude - camera.center.longitude) <= camera.longitudeSpan / 2
        else { return false }
        let y = min(180, max(-180, MapViewport.mercatorY(coordinate.latitude)))
        return mercatorBounds.contains(y)
    }

    /// The supplied request may be smaller or differently centred, but every
    /// drawable geographic position must remain inside this retained region.
    func covers(_ request: Self) -> Bool {
        if camera.longitudeSpan < 360 {
            guard request.camera.longitudeSpan <= camera.longitudeSpan else { return false }
            let longitude = MapViewport.unwrap(request.camera.center.longitude, near: camera.center.longitude)
            guard abs(longitude - camera.center.longitude) + request.camera.longitudeSpan / 2
                    <= camera.longitudeSpan / 2
            else { return false }
        }
        let bounds = mercatorBounds
        let requested = request.mercatorBounds
        return bounds.lowerBound <= requested.lowerBound && bounds.upperBound >= requested.upperBound
    }

    private var mercatorBounds: ClosedRange<Double> {
        let center = min(180, max(-180, MapViewport.mercatorY(camera.center.latitude)))
        let halfHeight = camera.longitudeSpan * Double(viewport.rows) * viewport.cellAspectRatio
            / (2 * Double(viewport.columns))
        return max(-180, center - halfHeight)...min(180, center + halfHeight)
    }
}

extension MapTileRequest: Hashable {}
extension MapTileRequest: Codable {}
extension MapTileRequest: Sendable {}
