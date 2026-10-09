import SwiftTUI

struct MapSpikeApplication {
    private let launch: Launch

    /// Native App requires a default initializer; it has no loaded source to display.
    nonisolated init() { launch = .unconfigured }

    nonisolated init(fixtures: MapFixtures, scene: MapFixtures.Scene, appearance: MapSpikeCommand.Appearance,
                     inspectSmall: Bool = false, cellAspect: Double? = nil, detail: MapDetail = .minimal) {
        launch = .map(fixtures: fixtures, scene: scene, appearance: appearance,
                      inspectSmall: inspectSmall, cellAspect: cellAspect, detail: detail)
    }

    private enum Launch {
        case unconfigured
        case map(fixtures: MapFixtures, scene: MapFixtures.Scene, appearance: MapSpikeCommand.Appearance,
                 inspectSmall: Bool, cellAspect: Double?, detail: MapDetail)
    }
}

extension MapSpikeApplication: SwiftTUIRuntime.App {
    var body: some Scene {
        WindowGroup("Chio map rendering spike") {
            switch launch {
            case .unconfigured:
                Text("Run chio-map-spike to load the offline examples.")
            case .map(let fixtures, let scene, let appearance, let inspectSmall, let cellAspect, let detail):
                if let cellAspect {
                    MapSpikeView(fixtures: fixtures, scene: scene, appearance: appearance,
                                 inspectSmall: inspectSmall, detail: detail)
                        .environment(\.cellPixelMetrics, CellPixelMetrics(width: 100, height: Int(cellAspect * 100), source: .reported))
                } else {
                    MapSpikeView(fixtures: fixtures, scene: scene, appearance: appearance,
                                 inspectSmall: inspectSmall, detail: detail)
                }
            }
        }
    }
}
