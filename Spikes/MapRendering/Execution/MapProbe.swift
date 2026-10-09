import Chio
import Foundation
import SwiftTUI

/// Explicit measurement/export effects for the spike, not part of geographic values.
@MainActor
enum MapProbe {
    static func run(fixtures: MapFixtures, appearance: MapSpikeCommand.Appearance, aspect: Double,
                    detail: MapDetail = .minimal) throws {
        let clock = ContinuousClock()
        var results: [Measurement] = []
        for scene in MapFixtures.Scene.allCases {
            let dataset = fixtures.dataset(for: scene)
            for (columns, rows) in [(100, 30), (60, 20), (36, 18)] {
                let viewport = try MapViewport(columns: columns, rows: rows, cellAspectRatio: aspect)
                var preparation: [Double] = []
                var drawingSetup: [Double] = []
                var rendering: [Double] = []
                var vertices = 0
                var features = 0
                var visibleLabels = 0
                var geometryElements = 0, edgeVisits = 0, sortWeight = 0, fillWrites = 0, strokeSamples = 0
                for iteration in 0..<21 {
                    let camera = try scene.camera.panned(longitudeFraction: Double(iteration) / 1000, latitudeFraction: 0)
                    let before = clock.now
                    let map = try MapPreparation.prepare(dataset: dataset, camera: camera, viewport: viewport, detail: detail)
                    let prepared = clock.now
                    let theme = appearance.theme
                    let view = try MapCanvasView(map: map, viewport: viewport, theme: theme, fills: true, labels: true,
                                             waterColor: theme.colors.selectedSurface, parkColor: theme.colors.selectedSurface, detail: detail)
                    let admitted = clock.now
                    let snapshot = DefaultRenderer().render(view, proposal: .init(width: columns, height: rows), frameInstant: .zero)
                    guard snapshot.rasterSurface.size == CellSize(width: columns, height: rows) else {
                        throw ValidationError("The map did not receive the requested allocation.")
                    }
                    if iteration > 0 {
                        preparation.append(milliseconds(before.duration(to: prepared)))
                        drawingSetup.append(milliseconds(prepared.duration(to: admitted)))
                        rendering.append(milliseconds(admitted.duration(to: clock.now)))
                    }
                    vertices = max(vertices, map.statistics.preparedVertices)
                    features = max(features, map.statistics.visibleFeatures)
                    visibleLabels = max(visibleLabels, MapLabels(candidates: map.labels, columns: columns, rows: rows,
                                                                 enabled: true, detail: detail).labels.count)
                    geometryElements = max(geometryElements, view.drawing.work.geometryElements)
                    edgeVisits = max(edgeVisits, view.drawing.work.edgeVisits)
                    sortWeight = max(sortWeight, view.drawing.work.crossingSortWeight)
                    fillWrites = max(fillWrites, view.drawing.work.fillWrites)
                    strokeSamples = max(strokeSamples, view.drawing.work.strokeSamples)
                }
                results.append(Measurement(scene: scene.rawValue, detail: detail,
                                           columns: columns, rows: rows, cellAspect: aspect,
                                           sourceFeatures: dataset.features.count, sourceVertices: dataset.vertexCount,
                                           peakPreparedVertices: vertices, peakVisibleFeatures: features, peakLabels: visibleLabels,
                                           peakGeometryElements: geometryElements, peakEdgeVisits: edgeVisits,
                                           peakCrossingSortWeight: sortWeight, peakFillWrites: fillWrites,
                                           peakStrokeSamples: strokeSamples,
                                           preparationMedianMS: median(preparation), preparationMaxMS: preparation.max()!,
                                           drawingSetupMedianMS: median(drawingSetup), drawingSetupMaxMS: drawingSetup.max()!,
                                           rasterMedianMS: median(rendering), rasterMaxMS: rendering.max()!))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(results), as: UTF8.self))
    }

    static func export(_ raster: RasterSurface, background: Color, foreground: Color) throws {
        let cells = raster.cells.map { row in
            row.map { cell in
                Pixel(character: String(cell.character), foreground: cell.style?.foregroundColor ?? foreground,
                      background: cell.style?.backgroundColor ?? background)
            }
        }
        let data = try JSONEncoder().encode(cells)
        print(String(decoding: data, as: UTF8.self))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
    private static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    private struct Pixel: Encodable {
        let character: String
        let foreground: Color
        let background: Color
    }

    private struct Measurement: Encodable {
        let scene: String
        let detail: MapDetail
        let columns: Int
        let rows: Int
        let cellAspect: Double
        let sourceFeatures: Int
        let sourceVertices: Int
        let peakPreparedVertices: Int
        let peakVisibleFeatures: Int
        let peakLabels: Int
        let peakGeometryElements: Int
        let peakEdgeVisits: Int
        let peakCrossingSortWeight: Int
        let peakFillWrites: Int
        let peakStrokeSamples: Int
        let preparationMedianMS: Double
        let preparationMaxMS: Double
        let drawingSetupMedianMS: Double
        let drawingSetupMaxMS: Double
        let rasterMedianMS: Double
        let rasterMaxMS: Double
    }
}
