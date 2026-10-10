import Chio
import Foundation
import SwiftTUI

@main
struct MapExampleCommand {
    @Option(name: .customLong("map"), help: "Local map: world or street.")
    var scene: MapFixtures.Scene = .world
    @Option(help: "Street source: overpass or openfreemap; retained while viewing world.")
    var source: MapFixtures.StreetSource = .overpass
    @Flag(help: "Load OpenFreeMap tiles online for world, region and street views.")
    var online = false
    @Option(help: "Optional JSON OpenMapTilesSource file for --online; otherwise discover OpenFreeMap.")
    var tileSource = ""
    @Option(help: "Opt-in dedicated disk cache directory for --online. A directory belongs to one exact tile source.")
    var tileCache = ""
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
                                                     abstract: "World and street examples using Chio MapView; offline unless --online is supplied.")
    mutating func validate() throws {
        let hasSupportedWidth = (20...240).contains(width)
        let hasSupportedHeight = (12...100).contains(height)
        guard hasSupportedWidth, hasSupportedHeight else {
            throw ValidationError("Use width 20...240 and height 12...100.")
        }
        if let cellAspect {
            let isFiniteAspect = cellAspect.isFinite
            let hasSupportedAspect = (0.5...4).contains(cellAspect)
            guard isFiniteAspect, hasSupportedAspect else {
                throw ValidationError("Cell aspect must be finite in 0.5...4.")
            }
        }
        guard [snapshot, snapshotJSON, benchmark].filter({ $0 }).count <= 1 else {
            throw ValidationError("Choose one output mode: snapshot, snapshot-json or benchmark.")
        }
        let hasOfflineOutput = snapshot || snapshotJSON || benchmark
        guard !online || !hasOfflineOutput else {
            throw ValidationError("Online mode is interactive. Snapshot and benchmark modes use bundled data.")
        }
        let isDefaultBundledSource: Bool
        switch source {
        case .overpass: isDefaultBundledSource = true
        case .openfreemap: isDefaultBundledSource = false
        }
        guard !online || isDefaultBundledSource else {
            throw ValidationError("--source selects a bundled fixture. Use --online on its own for live OpenFreeMap tiles.")
        }
        guard online || tileSource.isEmpty else {
            throw ValidationError("--tile-source requires --online.")
        }
        guard online || tileCache.isEmpty else {
            throw ValidationError("--tile-cache requires --online.")
        }
    }

    @MainActor
    mutating func run() async throws {
        let fixtures = try MapFixtures.load()
        let detail: MapDetail = sourceDetail ? .source : self.detail
        let acquisition: MapExampleAcquisition
        if online {
            if tileSource.isEmpty {
                acquisition = .openFreeMap
            } else {
                acquisition = try .configured(file: tileSource)
            }
        } else {
            acquisition = .offline
        }
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
            let cacheOwner: MapTileCache?
            let liveAcquisition: MapExampleAcquisition
            if tileCache.isEmpty {
                cacheOwner = nil
                liveAcquisition = acquisition
            } else {
                let cache: MapTileCache
                do { cache = try await acquisition.openCache(directory: URL(fileURLWithPath: tileCache)) }
                catch MapTileCache.CacheError.alreadyInUse {
                    throw ValidationError("Tile cache is already in use. Close its other map session or choose another directory.")
                } catch MapTileCache.CacheError.sourceMismatch {
                    throw ValidationError("Tile cache belongs to a different source. Choose another --tile-cache directory.")
                }
                cacheOwner = cache
                liveAcquisition = .cached(MapTileLoader(cache: cache))
            }
            do {
                try await WebHostCLIRunner.run(MapExampleApplication(fixtures: fixtures, scene: scene, appearance: theme,
                                                               cellAspect: cellAspect,
                                                               detail: detail, streetSource: source, acquisition: liveAcquisition),
                                          configuration: swiftTUIOptions.runtimeConfiguration())
            } catch {
                await cacheOwner?.close()
                throw error
            }
            await cacheOwner?.close()
        }
    }
}
