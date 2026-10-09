@testable import ChioMapSpike
import Foundation
import Testing

struct MapShapeSimplificationTests {
    @Test("Closed-ring generalization changes fill, retains extrema/winding and leaves input unchanged")
    func bayShape() {
        let original = [bay()]
        let captured = original
        let reduced = simplify(original, tolerance: 1.5)
        #expect(reduced[0].count == 7)
        #expect(signedArea(original[0]) == 396)
        #expect(signedArea(reduced[0]) == 400)
        #expect(simplify(original, tolerance: 0.75)[0].count > reduced[0].count)
        #expect(reduced[0].first == reduced[0].last)
        #expect(Set(reduced[0].dropLast()).count == 6)
        #expect(original == captured)
        let reversed = [Array(original[0].reversed())]
        #expect(signedArea(simplify(reversed, tolerance: 1.5)[0]) == -400)
    }

    @Test("Physical tolerance scales rows with cell aspect and pans only translate geometry")
    func aspectAndPan() {
        let original = [bay()]
        let tall = original.map { $0.map { PreparedMap.Point(x: $0.x, y: $0.y / 2) } }
        let ordinary = simplify(original, tolerance: 0.75)
        let tallReduced = simplify(tall, tolerance: 0.75, aspect: 2)
        #expect(tallReduced == ordinary.map { $0.map { .init(x: $0.x, y: $0.y / 2) } })
        let translated = original.map { $0.map { PreparedMap.Point(x: $0.x + 71, y: $0.y - 19) } }
        #expect(simplify(translated, tolerance: 1.5)
                == simplify(original, tolerance: 1.5).map { $0.map { .init(x: $0.x + 71, y: $0.y - 19) } })
        let zoomed = original.map { $0.map { PreparedMap.Point(x: $0.x * 2, y: $0.y * 2) } }
        #expect(simplify(zoomed, tolerance: 1.5)[0].count > simplify(original, tolerance: 1.5)[0].count)
    }

    @Test("Narrow water rings and excessive area changes fall back instead of vanishing")
    func narrowWater() {
        let narrow = [rectangle(0, 0, 20, 0.1)]
        #expect(simplify(narrow, tolerance: 1.5) == narrow)
        let channel: [[PreparedMap.Point]] = [[.init(x: 0, y: 0), .init(x: 6, y: 0),
                                              .init(x: 6, y: 1), .init(x: 14, y: 1),
                                              .init(x: 14, y: 0), .init(x: 20, y: 0),
                                              .init(x: 20, y: 2), .init(x: 0, y: 2), .init(x: 0, y: 0)]]
        #expect(simplify(channel, tolerance: 1.5) == channel) // Filling this bay would add 25% area.
    }

    @Test("Accepted holes remain contained; crossing or nested holes trigger exact fallback")
    func holes() {
        let safe = [bay(), rectangle(5, 5, 7, 7)]
        let reduced = simplify(safe, tolerance: 1.5)
        #expect(reduced[0].count == 7)
        #expect(reduced[1] == safe[1])
        let crossing = [bay(), rectangle(19, 5, 21, 7)]
        #expect(simplify(crossing, tolerance: 1.5) == crossing)
        let nested = [bay(), rectangle(4, 4, 8, 8), rectangle(5, 5, 6, 6)]
        #expect(simplify(nested, tolerance: 1.5) == nested)
        let touching = [bay(), rectangle(0, 5, 2, 7)]
        #expect(simplify(touching, tolerance: 1.5) == touching)
        // The exterior's small elbow is safe to remove on its own, but that
        // shortcut would cut through the hole. Reject the complete candidate.
        let elbow: [PreparedMap.Point] = [.init(x: 0, y: 0), .init(x: 20, y: 0),
                                         .init(x: 19, y: 18), .init(x: 18, y: 19.8),
                                         .init(x: 0, y: 20), .init(x: 0, y: 0)]
        #expect(simplify([elbow], tolerance: 1.5)[0].count < elbow.count)
        let endangered = [elbow, rectangle(18.7, 17, 18.9, 17.2)]
        #expect(simplify(endangered, tolerance: 1.5) == endangered)
    }

    @Test("Self crossing source rings are never silently repaired")
    func sourceCrossing() {
        let crossing: [[PreparedMap.Point]] = [[.init(x: 0, y: 0), .init(x: 2, y: 1.9),
                                               .init(x: 20, y: 20), .init(x: 0, y: 20),
                                               .init(x: 20, y: 0), .init(x: 20, y: -10), .init(x: 0, y: 0)]]
        #expect(simplify(crossing, tolerance: 1.5) == crossing)
    }

    @Test("Distance and topology budget exhaustion return the whole original polygon")
    func budgetFallback() {
        let original = [bay(), rectangle(5, 5, 7, 7)]
        for allowance in [0, 1, 10, 35] {
            var budget = allowance
            #expect(MapShapeSimplification.simplify(original, tolerance: 1.5, cellAspectRatio: 1,
                                                     operationBudget: &budget) == original)
            #expect(budget >= 0 && budget <= allowance)
        }
        #expect(simplify(original, tolerance: 1.5) != original)
    }

    private func simplify(_ rings: [[PreparedMap.Point]], tolerance: Double,
                          aspect: Double = 1) -> [[PreparedMap.Point]] {
        var budget = MapShapeSimplification.operationLimit
        return MapShapeSimplification.simplify(rings, tolerance: tolerance, cellAspectRatio: aspect,
                                               operationBudget: &budget)
    }

    private func bay() -> [PreparedMap.Point] {
        [.init(x: 0, y: 0), .init(x: 8, y: 0), .init(x: 8, y: 1), .init(x: 12, y: 1),
         .init(x: 12, y: 0), .init(x: 20, y: 0), .init(x: 20, y: 20),
         .init(x: 0, y: 20), .init(x: 0, y: 0)]
    }

    private func rectangle(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> [PreparedMap.Point] {
        [.init(x: left, y: top), .init(x: right, y: top), .init(x: right, y: bottom),
         .init(x: left, y: bottom), .init(x: left, y: top)]
    }

    private func signedArea(_ ring: [PreparedMap.Point]) -> Double {
        zip(ring, ring.dropFirst()).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y } / 2
    }
}
