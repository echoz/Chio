import Chio
import Foundation
import SwiftTUI

@main
struct MapExampleCommand {
    @Option(name: .customLong("map"), help: "Local map: world or street.")
    var scene: MapFixtures.Scene = .world
    @Option(help: "Street source: overpass or openfreemap; retained while viewing world.")
    var source: MapFixtures.StreetSource = .overpass
    @Option(help: "Theme: default, light or btop.") var theme: Appearance = .default
    @Flag(help: "Print a deterministic native raster as text.") var snapshot = false
    @Flag(help: "Export native raster cells as JSON for visual inspection.") var snapshotJSON = false
    @Flag(help: "Measure the first completed hosted frame, including compact fallbacks, at three terminal sizes.") var benchmark = false
    @Option(help: "Detail: silhouette, minimal, abstract or source.") var detail: MapDetail = .minimal
    @Flag(help: "Alias for --detail source; takes precedence over --detail.") var sourceDetail = false
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

extension MapExampleCommand.Appearance: ExpressibleByArgument {}
extension MapExampleCommand.Appearance: CaseIterable {}
extension MapExampleCommand.Appearance: Hashable {}
extension MapExampleCommand.Appearance: Codable {}
extension MapExampleCommand.Appearance: Sendable {}

extension MapDetail: ExpressibleByArgument {}

extension MapExampleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "chio-maps",
                                                     abstract: "Offline world and street examples using Chio MapView.")
    mutating func validate() throws {
        guard (20...240).contains(width), (12...100).contains(height) else {
            throw ValidationError("Use width 20...240 and height 12...100.")
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
        let detail: MapDetail = sourceDetail ? .source : self.detail
        if benchmark {
            try await MapCapture.benchmark(fixtures: fixtures, appearance: theme, cellAspect: cellAspect,
                                           detail: detail, streetSource: source)
        } else if snapshot || snapshotJSON {
            let capture = try await MapCapture.snapshot(fixtures: fixtures, scene: scene, appearance: theme,
                                                        width: width, height: height, cellAspect: cellAspect,
                                                        detail: detail, streetSource: source)
            if snapshotJSON {
                try MapCapture.export(capture.raster, background: theme.theme.colors.surface,
                                      foreground: theme.theme.colors.foreground)
            } else { print(capture.raster.lines.joined(separator: "\n")) }
        } else {
            try await WebHostCLIRunner.run(MapExampleApplication(fixtures: fixtures, scene: scene, appearance: theme,
                                                               cellAspect: cellAspect,
                                                               detail: detail, streetSource: source),
                                          configuration: swiftTUIOptions.runtimeConfiguration())
        }
    }
}
