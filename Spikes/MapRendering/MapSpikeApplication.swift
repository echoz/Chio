import SwiftTUI

struct MapSpikeApplication {
    let fixtures: MapFixtures
    let scene: MapFixtures.Scene
    let appearance: MapSpikeCommand.Appearance
    let inspectSmall: Bool
    let cellAspect: Double?

    nonisolated init() {
        // Required by App. Actual CLI loading is explicit and uses the initializer below.
        let empty = try! MapDataset(features: [])
        self.init(fixtures: MapFixtures(world: empty, street: empty), scene: .world, appearance: .default,
                  inspectSmall: false, cellAspect: nil)
    }

    nonisolated init(fixtures: MapFixtures, scene: MapFixtures.Scene, appearance: MapSpikeCommand.Appearance,
                     inspectSmall: Bool = false, cellAspect: Double? = nil) {
        self.fixtures = fixtures
        self.scene = scene
        self.appearance = appearance
        self.inspectSmall = inspectSmall
        self.cellAspect = cellAspect
    }
}

extension MapSpikeApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio map rendering spike") {
            if let cellAspect {
                MapSpikeView(fixtures: fixtures, scene: scene, appearance: appearance, inspectSmall: inspectSmall)
                    .environment(\.cellPixelMetrics, CellPixelMetrics(width: 100, height: Int(cellAspect * 100), source: .reported))
            } else {
                MapSpikeView(fixtures: fixtures, scene: scene, appearance: appearance, inspectSmall: inspectSmall)
            }
        }
    }
}
