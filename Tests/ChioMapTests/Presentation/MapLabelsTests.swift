@testable import ChioMaps
@testable import Chio
import Testing

@MainActor
struct MapLabelsTests {
    @Test("Detail budgets grow with allocation and retain the source default")
    func budgets() {
        let candidates = (0..<40).map { index in
            label(index, column: 10 + (index % 8) * 20, row: 3 + (index / 8) * 5)
        }
        let compact = MapDetail.allCases.map {
            MapLabels(candidates: candidates, columns: 100, rows: 20, enabled: true, detail: $0).labels.count
        }
        #expect(compact == [2, 4, 6, 20])
        let large = MapDetail.allCases.map {
            MapLabels(candidates: candidates, columns: 200, rows: 40, enabled: true, detail: $0).labels.count
        }
        #expect(large == [2, 4, 8, 40])
        #expect(MapLabels(candidates: candidates, columns: 100, rows: 20, enabled: true)
                == MapLabels(candidates: candidates, columns: 100, rows: 20, enabled: true, detail: .source))
    }

    @Test("Small allocations still permit one suitable label at every level", arguments: MapDetail.allCases)
    func smallAllocation(detail: MapDetail) {
        let candidates = [label(0, column: 4, row: 2), label(1, column: 15, row: 6)]
        let placed = MapLabels(candidates: candidates, columns: 20, rows: 8, enabled: true, detail: detail)
        #expect(placed.labels.map(\.id) == ["place-00"])
        #expect(MapLabels(candidates: candidates, columns: 20, rows: 8,
                          enabled: false, detail: detail).labels.isEmpty)
    }

    @Test("Reduced labels have wider row and column clearance than abstract labels",
          arguments: [MapDetail.silhouette, .minimal])
    func reducedSpacing(detail: MapDetail) {
        let origin = label(0, column: 20, row: 8)
        for neighbor in [label(1, column: 20, row: 11), label(1, column: 25, row: 8)] {
            let candidates = [neighbor, origin]
            #expect(MapLabels(candidates: candidates, columns: 100, rows: 20,
                              enabled: true, detail: detail).labels.map(\.id) == ["place-00"])
            #expect(MapLabels(candidates: candidates, columns: 100, rows: 20,
                              enabled: true, detail: .abstract).labels.count == 2)
        }
        let clear = [origin, label(1, column: 20, row: 12)]
        #expect(MapLabels(candidates: clear, columns: 100, rows: 20,
                          enabled: true, detail: detail).labels.count == 2)
    }

    @Test("Stable placement and native Unicode width apply at every detail", arguments: MapDetail.allCases)
    func stablePlacement(detail: MapDetail) {
        let candidates: [PreparedMap.Label] = [
            .init(featureID: "water", kind: .water, text: "界e\u{301}", position: .init(x: 20, y: 8)),
            .init(featureID: "road", kind: .primaryRoad, text: "Road", position: .init(x: 20, y: 8)),
            .init(featureID: "duplicate", kind: .land, text: "界e\u{301}", position: .init(x: 80, y: 14)),
            .init(featureID: "edge", kind: .land, text: "Edge", position: .init(x: 0, y: 0)),
        ]
        let placed = MapLabels(candidates: candidates, columns: 100, rows: 20, enabled: true, detail: detail)
        #expect(placed.labels.map(\.id) == ["water"])
        #expect(placed.labels.first?.width == 3)
        #expect(MapLabels(candidates: Array(candidates.reversed()), columns: 100, rows: 20,
                          enabled: true, detail: detail) == placed)
    }

    private func label(_ index: Int, column: Int, row: Int) -> PreparedMap.Label {
        let suffix = index < 10 ? "0\(index)" : "\(index)"
        return PreparedMap.Label(featureID: "place-\(suffix)", kind: .water,
                                 text: "\(index)", position: .init(x: Double(column), y: Double(row)))
    }
}
