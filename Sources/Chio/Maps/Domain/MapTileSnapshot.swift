/// A complete acquired source correlated to its camera and drawing allocation.
public struct MapTileSnapshot {
    public let request: MapTileRequest
    public let source: MapSource
    public let requestedZoom: Int

    public init(request: MapTileRequest, source: MapSource, requestedZoom: Int) throws {
        switch source.coverage {
        case .worldwide, .boundedOfflineExtract: throw MapValidationError.invalidTileSnapshot
        case .tiled(let coverage):
            let isSupportedZoom = (0...22).contains(requestedZoom)
            let isAtLeastAttainedZoom = requestedZoom >= coverage.zoom
            guard isSupportedZoom, isAtLeastAttainedZoom else { throw MapValidationError.invalidTileSnapshot }
            guard coverage.covers(request) else { throw MapValidationError.invalidTileSnapshot }
        }
        self.request = request
        self.source = source
        self.requestedZoom = requestedZoom
    }

    public var attainedZoom: Int {
        // Checked construction and decoding establish tiled coverage.
        switch source.coverage {
        case .tiled(let coverage): return coverage.zoom
        case .worldwide, .boundedOfflineExtract:
            preconditionFailure("A tile snapshot requires tiled coverage")
        }
    }
}

extension MapTileSnapshot: Hashable {}
extension MapTileSnapshot: Sendable {}
extension MapTileSnapshot: Codable {
    private enum CodingKeys: String, CodingKey { case request, source, requestedZoom }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(request: values.decode(MapTileRequest.self, forKey: .request),
                      source: values.decode(MapSource.self, forKey: .source),
                      requestedZoom: values.decode(Int.self, forKey: .requestedZoom))
    }
}
