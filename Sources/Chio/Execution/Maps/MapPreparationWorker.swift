import Foundation

/// One mounted map owns one serial worker. Cancelled queued requests do no work.
actor MapPreparationWorker {
    private let operation: @Sendable (MapPreparationRequest) throws -> PreparedMapDrawing

    init(operation: @escaping @Sendable (MapPreparationRequest) throws -> PreparedMapDrawing = MapPreparationWorker.makeDrawing) {
        self.operation = operation
    }

    func prepare(_ request: MapPreparationRequest) throws -> PreparedMapDrawing {
        try Task.checkCancellation()
        let drawing = try operation(request)
        try Task.checkCancellation()
        return drawing
    }

    private static func makeDrawing(_ request: MapPreparationRequest) throws -> PreparedMapDrawing {
        let map = try MapPreparation.prepare(dataset: request.dataset, camera: request.camera,
                                             viewport: request.viewport, detail: request.detail,
                                             isCancelled: { Task.isCancelled })
        try Task.checkCancellation()
        // Overlay identities are independent of the geography and retain every
        // route at every detail level. They are clipped by the same projection.
        let dataset = try MapDataset(features: request.routes.map {
            try MapFeature(id: $0.id, kind: .primaryRoad, name: $0.title, geometry: .polyline($0.path))
        })
        let routes = try MapPreparation.prepare(dataset: dataset, camera: request.camera,
                                                viewport: request.viewport, detail: .source,
                                                isCancelled: { Task.isCancelled })
        try Task.checkCancellation()
        return try PreparedMapDrawing(map: map, routes: routes.lines, viewport: request.viewport, fills: request.fills,
                                      routeLabels: routes.labels)
    }
}
