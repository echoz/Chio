public struct MapFeature {
    public let id: String
    public let kind: Kind
    public let name: String
    public let geometry: MapGeometry

    public init(id: String, kind: Kind, name: String = "", geometry: MapGeometry) throws {
        guard !id.isEmpty, id.utf8.count <= 256,
              !id.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { throw MapValidationError.invalidIdentity }
        try Self.validateName(name)
        self.id = id
        self.kind = kind
        self.name = name
        self.geometry = geometry
    }

    /// Adapters validate selected labels before geometry resource admission.
    /// Construction and decoding retain the same canonical name restriction.
    static func validateName(_ name: String) throws {
        guard name.utf8.count <= 256,
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { throw MapValidationError.invalidIdentity }
    }

    public enum Kind: String {
        case land, water, park, building, road, primaryRoad

        /// Stable paint/label order: area backgrounds first, prominent roads last.
        var priority: Int {
            switch self {
            case .land: 0
            case .water: 1
            case .park: 2
            case .building: 3
            case .road: 4
            case .primaryRoad: 5
            }
        }
    }
}

extension MapFeature: Hashable {}
extension MapFeature: Identifiable {}
extension MapFeature: Sendable {}
extension MapFeature: Codable {
    private enum CodingKeys: String, CodingKey { case id, kind, name, geometry }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(String.self, forKey: .id),
                      kind: values.decode(Kind.self, forKey: .kind),
                      name: values.decode(String.self, forKey: .name),
                      geometry: values.decode(MapGeometry.self, forKey: .geometry))
    }
}

extension MapFeature.Kind: Hashable {}
extension MapFeature.Kind: Codable {}
extension MapFeature.Kind: Sendable {}
