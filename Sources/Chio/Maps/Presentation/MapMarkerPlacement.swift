import SwiftTUIViews

/// Markers reserve space before optional geographic labels. Selection wins collisions.
struct MapMarkerPlacement {
    let markers: [Marker]
    let labels: [MapLabels.Label]
    let reservations: [MapLabels.Label]

    struct Marker {
        let value: MapMarker
        let column: Int
        let row: Int
        let isSelected: Bool
        let origin: CellPoint
        let glyph: BrailleCanvas

        init(value: MapMarker, position: PreparedMap.Point, isSelected: Bool, viewport: MapViewport) {
            self.value = value
            column = Int(position.x)
            row = Int(position.y)
            self.isSelected = isSelected
            if isSelected {
                let x = Int(position.x * 2), y = Int(position.y * 4)
                let left = max(0, x - 2) / 2, top = max(0, y - 2) / 4
                let right = min(viewport.columns - 1, (x + 2) / 2)
                let bottom = min(viewport.rows - 1, (y + 2) / 4)
                origin = CellPoint(x: left, y: top)
                var dots = BrailleCanvas(width: right - left + 1, height: bottom - top + 1)
                dots.strokeCircle(centerX: x - left * 2, centerY: y - top * 4, radius: 2)
                dots.setPixel(x: x - left * 2, y: y - top * 4)
                glyph = dots
            } else {
                origin = CellPoint(x: column, y: row)
                var dots = BrailleCanvas(width: 1, height: 1)
                for y in 1...2 {
                    for x in 0...1 { dots.setPixel(x: x, y: y) }
                }
                glyph = dots
            }
        }
    }

    init(markers values: [MapMarker], selection: String?, camera: MapCamera,
         viewport: MapViewport, showsLabels: Bool) {
        let ordered = values.filter { $0.id == selection } + values.filter { $0.id != selection }
        var placed: [Marker] = []
        var reserved: [MapLabels.Label] = []
        var acceptedLabels: [MapLabels.Label] = []
        func placeLabel(_ marker: Marker) {
            let measured = layoutText(for: marker.value.title, width: nil).size.width
            let rightEdge = marker.origin.x + marker.glyph.width
            let rightSpace = viewport.columns - rightEdge - 1
            let leftSpace = marker.origin.x - 1
            let width = min(32, measured, max(rightSpace, leftSpace))
            guard width > 0 else { return }
            let candidates = [rightEdge + 1, marker.origin.x - width - 1]
            guard let column = candidates.first(where: { x in
                x >= 0 && x + width <= viewport.columns && !reserved.contains {
                    $0.row == marker.row && x < $0.column + $0.width + 1 && x + width + 1 > $0.column
                }
            }) else { return }
            let label = MapLabels.Label(id: marker.value.id, text: marker.value.title,
                                        column: column, row: marker.row, width: width)
            acceptedLabels.append(label)
            reserved.append(label)
        }
        for value in ordered {
            let point = viewport.project(value.coordinate, camera: camera)
            guard point.x >= 0, point.y >= 0, point.x < Double(viewport.columns), point.y < Double(viewport.rows)
            else { continue }
            let marker = Marker(value: value, position: point, isSelected: value.id == selection, viewport: viewport)
            let occupiedRows = marker.origin.y..<(marker.origin.y + marker.glyph.height)
            guard !reserved.contains(where: {
                occupiedRows.contains($0.row) && marker.origin.x < $0.column + $0.width
                    && marker.origin.x + marker.glyph.width > $0.column
            }) else { continue }
            placed.append(marker)
            for row in occupiedRows {
                reserved.append(MapLabels.Label(id: value.id, text: "", column: marker.origin.x,
                                                row: row, width: marker.glyph.width))
            }
            // A selected name reserves its space before unselected marker glyphs.
            if marker.isSelected { placeLabel(marker) }
        }
        for marker in placed where !marker.isSelected && showsLabels { placeLabel(marker) }
        markers = placed
        labels = acceptedLabels
        reservations = reserved
    }
}

extension MapMarkerPlacement.Marker: Equatable {}
extension MapMarkerPlacement.Marker: Sendable {}
extension MapMarkerPlacement.Marker: CanvasDrawing {
    func draw(into context: inout CanvasContext) {
        for y in 0..<glyph.subpixelHeight {
            for x in 0..<glyph.subpixelWidth where glyph.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4) {
                context.setSample(GridSample(x: x, y: y))
            }
        }
    }
}
extension MapMarkerPlacement: Equatable {}
extension MapMarkerPlacement: Sendable {}
