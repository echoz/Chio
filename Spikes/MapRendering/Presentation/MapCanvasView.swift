import Chio
import SwiftTUI

@MainActor
struct MapCanvasView {
    let drawing: MapDrawing
    let positioned: MapLabels

    init(map: PreparedMap, viewport: MapViewport, theme: ChioTheme, fills: Bool, labels: Bool,
         waterColor: Color, parkColor: Color, detail: MapDetail = .source) throws {
        drawing = try MapDrawing(map: map, viewport: viewport, colors: theme.colors,
                                 waterColor: waterColor, parkColor: parkColor, fills: fills)
        positioned = MapLabels(candidates: map.labels, columns: viewport.columns,
                               rows: viewport.rows, enabled: labels, detail: detail)
    }
}

extension MapCanvasView: View {
    var body: some View {
        let viewport = drawing.viewport
        ZStack(alignment: .topLeading) {
            Canvas(drawing, grid: .braille2x4)
            ForEach(positioned.labels, id: \.id) { label in
                Text(verbatim: label.text)
                    .foregroundStyle(drawing.colors.foreground)
                    .background(drawing.colors.surface)
                    .frame(width: label.width, height: 1, alignment: .leading)
                    .offset(x: label.column, y: label.row)
            }
        }
        .frame(width: viewport.columns, height: viewport.rows, alignment: .topLeading)
        .clipped()
        .accessibilityLabel("Map with \(drawing.map.statistics.visibleFeatures) visible features and \(positioned.labels.count) labels")
    }
}
