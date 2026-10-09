import Chio
import SwiftTUI

@MainActor
struct MapCanvasView {
    let map: PreparedMap
    let viewport: MapViewport
    let theme: ChioTheme
    let fills: Bool
    let labels: Bool
    let waterColor: Color
    let parkColor: Color
}

extension MapCanvasView: View {
    var body: some View {
        let positioned = MapLabels(candidates: map.labels, columns: viewport.columns,
                                   rows: viewport.rows, enabled: labels)
        ZStack(alignment: .topLeading) {
            Canvas(MapDrawing(map: map, columns: viewport.columns, rows: viewport.rows,
                              colors: theme.colors, waterColor: waterColor, parkColor: parkColor, fills: fills),
                   grid: .braille2x4)
            ForEach(positioned.labels, id: \.id) { label in
                Text(verbatim: label.text)
                    .foregroundStyle(theme.colors.foreground)
                    .background(theme.colors.surface)
                    .frame(width: label.width, height: 1, alignment: .leading)
                    .offset(x: label.column, y: label.row)
            }
        }
        .frame(width: viewport.columns, height: viewport.rows, alignment: .topLeading)
        .clipped()
        .accessibilityLabel("Map with \(map.statistics.visibleFeatures) visible features and \(positioned.labels.count) labels")
    }
}
