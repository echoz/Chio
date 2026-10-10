/// Geometry admitted for one allocation. Theme changes need no new preparation.
struct PreparedMapDrawing {
    let map: PreparedMap
    let routes: [PreparedMap.Line]
    let routeLabels: [PreparedMap.Label]
    let viewport: MapViewport
    let fills: Bool
    let work: MapDrawingWork

    init(map: PreparedMap, routes: [PreparedMap.Line], viewport: MapViewport, fills: Bool,
         routeLabels: [PreparedMap.Label] = []) throws {
        work = try MapDrawingWork(map: map, viewport: viewport, fills: fills, routes: routes)
        self.map = map
        self.routes = routes
        self.routeLabels = routeLabels
        self.viewport = viewport
        self.fills = fills
    }
}

extension PreparedMapDrawing: Equatable {}
extension PreparedMapDrawing: Sendable {}
