enum MapValidationError: Error, Equatable, Sendable {
    case invalidCoordinate
    case invalidCamera
    case invalidViewport
    case invalidIdentity
    case invalidPath
    case invalidRing
    case duplicateIdentity
    case unsupportedGeoJSON
    case budgetExceeded
}
