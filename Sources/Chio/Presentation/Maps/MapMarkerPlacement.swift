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
        let selected: Bool
    }

    init(markers values: [MapMarker], selection: String?, camera: MapCamera,
         viewport: MapViewport, showsLabels: Bool) {
        let ordered = values.filter { $0.id == selection } + values.filter { $0.id != selection }
        var placed: [Marker] = []
        var reserved: [MapLabels.Label] = []
        var acceptedLabels: [MapLabels.Label] = []
        func placeLabel(_ marker: Marker) {
            let measured = layoutText(for: marker.value.title, width: nil).size.width
            let rightSpace = viewport.columns - marker.column - 2
            let leftSpace = marker.column - 1
            let width = min(32, measured, max(rightSpace, leftSpace))
            guard width > 0 else { return }
            let candidates = [marker.column + 2, marker.column - width - 1]
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
            let column = Int(point.x), row = Int(point.y)
            guard !reserved.contains(where: { $0.row == row && ($0.column..<($0.column + $0.width)).contains(column) })
            else { continue }
            let marker = Marker(value: value, column: column, row: row, selected: value.id == selection)
            placed.append(marker)
            reserved.append(.init(id: value.id, text: "", column: column, row: row, width: 1))
            // A selected name reserves its space before unselected marker glyphs.
            if marker.selected { placeLabel(marker) }
        }
        for marker in placed where !marker.selected && showsLabels { placeLabel(marker) }
        markers = placed
        labels = acceptedLabels
        reservations = reserved
    }
}

extension MapMarkerPlacement.Marker: Equatable {}
extension MapMarkerPlacement.Marker: Sendable {}
extension MapMarkerPlacement: Equatable {}
extension MapMarkerPlacement: Sendable {}
