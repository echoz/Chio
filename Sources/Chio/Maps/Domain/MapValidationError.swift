public enum MapValidationError {
    case invalidCoordinate
    case invalidCamera
    case invalidViewport
    case invalidIdentity
    case invalidPath
    case invalidRing
    case duplicateIdentity
    case unsupportedGeoJSON
    case budgetExceeded
    case drawingBudgetExceeded
    case invalidTileSource
    case invalidTileCoverage
    case invalidTileSnapshot
    case tileLimitExceeded
}

extension MapValidationError: Error {}
extension MapValidationError: Equatable {}
extension MapValidationError: Sendable {}
