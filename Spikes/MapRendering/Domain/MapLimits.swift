/// Deliberately finite limits for the offline rendering experiment.
enum MapLimits {
    static let features = 4_000
    static let sourceVertices = 200_000
    static let pathVertices = 20_000
    static let polygonRings = 256
    static let preparedVertices = 600_000
    static let geoJSONBytes = 16 * 1_024 * 1_024
    static let columns = 240
    static let rows = 100
    static let mercatorLatitude = 85.0511287798066
    static let minimumLongitudeSpan = 0.0001
}
