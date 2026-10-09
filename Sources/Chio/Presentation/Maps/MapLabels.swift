import SwiftTUIViews

/// Uses native text measurement; arbitrary Unicode names are never written as Canvas cells.
struct MapLabels {
    let labels: [Label]

    struct Label {
        let id: String
        let text: String
        let column: Int
        let row: Int
        let width: Int
    }

    init(candidates: [PreparedMap.Label], columns: Int, rows: Int, enabled: Bool,
         detail: MapDetail = .source, reserved: [Label] = []) {
        guard enabled else { labels = []; return }
        var accepted: [Label] = []
        var names: Set<String> = []
        // Source order is made irrelevant, and repeated names label just once.
        let ordered = candidates.sorted {
            let a = Self.priority($0.kind), b = Self.priority($1.kind)
            return a == b ? $0.featureID < $1.featureID : a > b
        }
        for candidate in ordered {
            let text = candidate.text
            guard !text.isEmpty, !names.contains(text) else { continue }
            let width = layoutText(for: text, width: nil).size.width
            guard width > 0, width <= columns / 2 else { continue }
            let x = Int(candidate.position.x.rounded()) - width / 2
            let y = Int(candidate.position.y.rounded())
            guard x >= 1, y >= 1, x + width < columns, y < rows - 1 else { continue }
            guard !(reserved + accepted).contains(where: {
                abs($0.row - y) <= detail.labelRowGap
                    && x < $0.column + $0.width + detail.labelColumnGap
                    && x + width + detail.labelColumnGap > $0.column
            }) else { continue }
            accepted.append(Label(id: candidate.featureID, text: text, column: x, row: y, width: width))
            names.insert(text)
            let limit = detail.labelLimit(columns: columns, rows: rows)
            if accepted.count >= limit { break }
        }
        labels = accepted
    }

    private static func priority(_ kind: MapFeature.Kind) -> Int {
        switch kind {
        case .water: 6
        case .park: 5
        case .primaryRoad: 4
        case .road: 3
        case .building: 2
        case .land: 1
        }
    }
}

extension MapLabels.Label: Equatable {}
extension MapLabels.Label: Sendable {}
extension MapLabels: Equatable {}
extension MapLabels: Sendable {}
