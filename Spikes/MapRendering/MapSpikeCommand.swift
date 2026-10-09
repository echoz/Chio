import Chio
import Foundation
import SwiftTUI

@main
struct MapSpikeCommand {
    @Option(help: "Local fixture: world or street.") var scene: MapFixtures.Scene = .world
    @Option(help: "Theme: default, light or btop.") var theme: Appearance = .default
    @Flag(help: "Print a deterministic native raster as text.") var snapshot = false
    @Flag(help: "Export native raster cells as JSON for visual inspection.") var snapshotJSON = false
    @Flag(help: "Measure preparation and native raster time at three allocations.") var benchmark = false
    @Flag(help: "Render below the provisional minimum size to assess readability.") var inspectSmall = false
    @Option(help: "Snapshot width, 20...240 columns.") var width = 100
    @Option(help: "Snapshot height, 12...100 rows.") var height = 30
    @Option(help: "Override cell height/width, 0.5...4. Defaults to reported metrics interactively, estimated 2 for snapshots.")
    var cellAspect: Double?
    @OptionGroup(title: "SwiftTUI options") var swiftTUIOptions: SwiftTUIOptions

    enum Appearance: String {
        case `default`, light, btop
        var theme: ChioTheme {
            switch self {
            case .default: .default
            case .light: .light
            case .btop: .btop
            }
        }
        var next: Self {
            switch self {
            case .default: .light
            case .light: .btop
            case .btop: .default
            }
        }
    }
}

extension MapSpikeCommand.Appearance: ExpressibleByArgument {}
extension MapSpikeCommand.Appearance: CaseIterable {}
extension MapSpikeCommand.Appearance: Hashable {}
extension MapSpikeCommand.Appearance: Codable {}
extension MapSpikeCommand.Appearance: Sendable {}

extension MapSpikeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "chio-map-spike",
                                                     abstract: "Experimental offline world/street rendering proof. No public map API.")
    mutating func validate() throws {
        guard (20...240).contains(width), (12...100).contains(height) else {
            throw ValidationError("Use width20...240 and height12...100.")
        }
        if let cellAspect, !cellAspect.isFinite || !(0.5...4).contains(cellAspect) {
            throw ValidationError("Cell aspect must be finite in 0.5...4.")
        }
        guard [snapshot, snapshotJSON, benchmark].filter({ $0 }).count <= 1 else {
            throw ValidationError("Choose one output mode: snapshot, snapshot-json or benchmark.")
        }
    }

    @MainActor
    mutating func run() async throws {
        let fixtures = try MapFixtures.load()
        if benchmark {
            try MapProbe.run(fixtures: fixtures, appearance: theme, aspect: cellAspect ?? 2)
        } else if snapshot || snapshotJSON {
            let metrics = CellPixelMetrics(width: 100, height: Int((cellAspect ?? 2) * 100),
                                           source: cellAspect == nil ? .estimated : .reported)
            let frame = DefaultRenderer().render(
                MapSpikeView(fixtures: fixtures, scene: scene, appearance: theme, inspectSmall: inspectSmall)
                    .environment(\.terminalSize, CellSize(width: width, height: height))
                    .environment(\.cellPixelMetrics, metrics),
                proposal: ProposedSize(width: width, height: height), frameInstant: .zero)
            if snapshotJSON {
                try MapProbe.export(frame.rasterSurface, background: theme.theme.colors.surface,
                                    foreground: theme.theme.colors.foreground)
            } else { print(frame.rasterSurface.lines.joined(separator: "\n")) }
        } else {
            try await WebHostCLIRunner.run(MapSpikeApplication(fixtures: fixtures, scene: scene, appearance: theme,
                                                               inspectSmall: inspectSmall, cellAspect: cellAspect),
                                          configuration: swiftTUIOptions.runtimeConfiguration())
        }
    }
}
