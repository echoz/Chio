/// An application-authored path; Chio does not calculate routes.
public struct MapRoute {
    public let id: String
    /// An empty title omits the supporting route label.
    public let title: String
    public let path: MapPolyline

    public init(id: String, title: String = "", path: MapPolyline) throws {
        guard !id.isEmpty, id.utf8.count <= 256, title.utf8.count <= 256,
              !id.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !title.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { throw MapValidationError.invalidIdentity }
        self.id = id
        self.title = title
        self.path = path
    }
}

extension MapRoute: Hashable {}
extension MapRoute: Identifiable {}
extension MapRoute: Sendable {}
extension MapRoute: Codable {
    private enum CodingKeys: String, CodingKey { case id, title, path }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(String.self, forKey: .id),
                      title: values.decode(String.self, forKey: .title),
                      path: values.decode(MapPolyline.self, forKey: .path))
    }
}
