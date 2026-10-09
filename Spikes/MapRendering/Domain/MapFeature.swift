struct MapFeature {
    let id: String
    let kind: Kind
    let name: String
    let geometry: MapGeometry

    init(id: String, kind: Kind, name: String = "", geometry: MapGeometry) throws {
        guard !id.isEmpty, id.utf8.count <= 256, name.utf8.count <= 256,
              !id.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { throw MapValidationError.invalidIdentity }
        self.id = id
        self.kind = kind
        self.name = name
        self.geometry = geometry
    }

    enum Kind: String {
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
extension MapFeature: Sendable {}
extension MapFeature: Codable {
    private enum CodingKeys: String, CodingKey { case id, kind, name, geometry }

    init(from decoder: any Decoder) throws {
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
