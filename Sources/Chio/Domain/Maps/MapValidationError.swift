public enum MapValidationError: Error, Equatable, Sendable {
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
