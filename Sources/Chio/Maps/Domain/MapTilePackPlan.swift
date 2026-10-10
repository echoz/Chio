import Foundation

/// The complete XYZ footprint of a nonwrapping extract across its source zooms.
/// Byte limits count raw payloads; framing and bounded metadata are additional.
public struct MapTilePackPlan {
    public let bounds: MapCoverage.Bounds
    public let zoomRange: ClosedRange<Int>
    public let maximumBytes: Int
    public let tiles: [MapTileCoordinate]

    static let maximumTiles = 1_024
    static let hardMaximumBytes = 256 * 1_024 * 1_024

    public init(bounds: MapCoverage.Bounds, zoomRange: ClosedRange<Int>,
                maximumBytes: Int = 128 * 1_024 * 1_024) throws {
        let hasSupportedZooms = zoomRange.lowerBound >= 1 && zoomRange.upperBound <= 22
        let hasSupportedBudget = (1...Self.hardMaximumBytes).contains(maximumBytes)
        guard hasSupportedZooms, hasSupportedBudget else { throw ValidationError.invalidConfiguration }
        // Count every zoom before enumerating even the first address.
        var footprints: [Footprint] = []
        var count = 0
        for zoom in zoomRange {
            let footprint = Self.footprint(bounds: bounds, zoom: zoom)
            let width = footprint.lastX - footprint.firstX + 1
            let height = footprint.lastY - footprint.firstY + 1
            let remaining = Self.maximumTiles - count
            guard width <= remaining, height <= remaining / width else {
                throw ValidationError.tileLimitExceeded
            }
            count += width * height
            footprints.append(footprint)
        }
        var addresses: [MapTileCoordinate] = []
        addresses.reserveCapacity(count)
        for footprint in footprints {
            for x in footprint.firstX...footprint.lastX {
                for y in footprint.firstY...footprint.lastY {
                    addresses.append(try MapTileCoordinate(zoom: footprint.zoom, x: x, y: y))
                }
            }
        }
        self.bounds = bounds
        self.zoomRange = zoomRange
        self.maximumBytes = maximumBytes
        self.tiles = addresses
    }

    public enum ValidationError { case invalidConfiguration, tileLimitExceeded }

    private struct Footprint {
        let zoom: Int
        let firstX: Int
        let lastX: Int
        let firstY: Int
        let lastY: Int
    }

    private static func footprint(bounds: MapCoverage.Bounds, zoom: Int) -> Footprint {
        let side = 1 << zoom
        let scale = Double(side) / 360
        let west = MapTilePlan.boundary((bounds.southwest.longitude + 180) * scale, side: side)
        let east = MapTilePlan.boundary((bounds.northeast.longitude + 180) * scale, side: side)
        let north = MapTilePlan.boundary((180 - MapViewport.mercatorY(bounds.northeast.latitude)) * scale, side: side)
        let south = MapTilePlan.boundary((180 - MapViewport.mercatorY(bounds.southwest.latitude)) * scale, side: side)
        let firstX = max(0, min(side - 1, Int(floor(west))))
        let firstY = max(0, min(side - 1, Int(floor(north))))
        // Polar bounds and sub-roundoff spans still refer to one clamped tile.
        let lastX = max(firstX, min(side - 1, Int(ceil(east)) - 1))
        let lastY = max(firstY, min(side - 1, Int(ceil(south)) - 1))
        return Footprint(zoom: zoom, firstX: firstX, lastX: lastX, firstY: firstY, lastY: lastY)
    }
}

extension MapTilePackPlan: Hashable {}
extension MapTilePackPlan: Sendable {}
extension MapTilePackPlan: Codable {
    private enum CodingKeys: String, CodingKey { case bounds, zoomRange, maximumBytes }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(bounds: values.decode(MapCoverage.Bounds.self, forKey: .bounds),
                      zoomRange: values.decode(ClosedRange<Int>.self, forKey: .zoomRange),
                      maximumBytes: values.decode(Int.self, forKey: .maximumBytes))
    }
}

extension MapTilePackPlan.ValidationError: Error {}
extension MapTilePackPlan.ValidationError: Equatable {}
extension MapTilePackPlan.ValidationError: Sendable {}
