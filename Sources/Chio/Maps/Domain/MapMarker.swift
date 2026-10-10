/// An application-authored location, identified independently of source geography.
public struct MapMarker {
    public let id: String
    public let coordinate: MapCoordinate
    /// An empty title omits the supporting location label.
    public let title: String

    public init(id: String, coordinate: MapCoordinate, title: String = "") throws {
        guard !id.isEmpty, id.utf8.count <= 256, title.utf8.count <= 256,
              !id.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !title.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { throw MapValidationError.invalidIdentity }
        self.id = id
        self.coordinate = coordinate
        self.title = title
    }
}

extension MapMarker: Hashable {}
extension MapMarker: Identifiable {}
extension MapMarker: Sendable {}
extension MapMarker: Codable {
    private enum CodingKeys: String, CodingKey { case id, coordinate, title }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(String.self, forKey: .id),
                      coordinate: values.decode(MapCoordinate.self, forKey: .coordinate),
                      title: values.decode(String.self, forKey: .title))
    }
}
