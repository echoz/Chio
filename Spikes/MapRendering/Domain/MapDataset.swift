struct MapDataset {
    let features: [MapFeature]

    init(features: [MapFeature]) throws {
        guard features.count <= MapLimits.features,
              features.reduce(0, { $0 + $1.geometry.vertexCount }) <= MapLimits.sourceVertices
        else { throw MapValidationError.budgetExceeded }
        guard Set(features.map(\.id)).count == features.count else { throw MapValidationError.duplicateIdentity }
        self.features = features
    }

    var vertexCount: Int { features.reduce(0) { $0 + $1.geometry.vertexCount } }
}

extension MapDataset: Hashable {}
extension MapDataset: Sendable {}
