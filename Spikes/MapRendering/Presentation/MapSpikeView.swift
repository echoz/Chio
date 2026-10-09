import Chio
import Foundation
import SwiftTUI

@MainActor
struct MapSpikeView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.cellPixelMetrics) private var pixelMetrics
    @Environment(\.requestTermination) private var requestTermination
    @State private var scene: MapFixtures.Scene
    @State private var camera: MapCamera
    @State private var appearance: MapSpikeCommand.Appearance
    @State private var fills = true
    @State private var labels = true
    @State private var detail: MapDetail
    private let fixtures: MapFixtures
    private let inspectSmall: Bool

    init(fixtures: MapFixtures, scene: MapFixtures.Scene, appearance: MapSpikeCommand.Appearance,
         inspectSmall: Bool = false, detail: MapDetail = .minimal) {
        self.fixtures = fixtures
        self.inspectSmall = inspectSmall
        _scene = State(wrappedValue: scene)
        _camera = State(wrappedValue: scene.camera)
        _appearance = State(wrappedValue: appearance)
        _detail = State(wrappedValue: detail)
    }

    private var theme: ChioTheme { appearance.theme }
    private var source: MapSource { fixtures.source(for: scene) }
    private var sourceDescription: String {
        switch source.coverage {
        case .worldwide: "Offline world"
        case .boundedOfflineExtract:
            source.coverage.contains(camera.center) ? "Offline extract" : "Outside offline coverage · r reset"
        }
    }
    private var licenseText: String {
        let link = source.metadata.attributionURL ?? source.metadata.licenseURL
        return "\(source.metadata.license) · \(link.host ?? "")\(link.path)"
    }
    private var viewport: MapViewport {
        // Full-world Mercator is square in physical space. Letterboxing preserves
        // the poles' projection cutoff instead of stretching or cropping the world.
        let aspect = (0.5...4).contains(pixelMetrics.aspectRatio) ? pixelMetrics.aspectRatio : 2
        let rows = max(1, min(90, terminalSize.height - 10))
        let available = max(1, min(238, terminalSize.width - 2))
        let columns = scene == .world ? min(available, max(1, Int(Double(rows) * aspect))) : available
        return try! MapViewport(columns: columns, rows: rows, cellAspectRatio: aspect)
    }

    private var small: Bool {
        scene == .world ? viewport.columns < 32 || viewport.rows < 16
            : viewport.columns < 58 || viewport.rows < 16
    }

    private func tint(_ color: Color, amount: Double) -> Color {
        let base = theme.colors.surface
        return Color(red: base.red + (color.red - base.red) * amount,
                     green: base.green + (color.green - base.green) * amount,
                     blue: base.blue + (color.blue - base.blue) * amount)
    }

    @ViewBuilder
    private var mapView: some View {
        if small && !inspectSmall {
            VStack(alignment: .leading, spacing: 1) {
                Text("More room for the map").bold().foregroundStyle(theme.colors.accent)
                Text("Try 60 × 26 or larger.")
                Text("Camera retained · resize to continue")
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            switch Result(catching: {
                let map = try MapPreparation.prepare(dataset: fixtures.dataset(for: scene),
                                                     camera: camera, viewport: viewport, detail: detail)
                return try MapCanvasView(map: map, viewport: viewport, theme: theme, fills: fills, labels: labels,
                                         waterColor: tint(theme.syntax.type, amount: 0.22),
                                         parkColor: tint(theme.syntax.string, amount: 0.16), detail: detail)
            }) {
            case .success(let view):
                view
            case .failure(MapValidationError.drawingBudgetExceeded):
                VStack(alignment: .leading, spacing: 1) {
                    Text("Too much map detail").bold().foregroundStyle(theme.colors.accent)
                    Text("Try another scale, [ lower detail, or f turn off fills.")
                    Text("Camera retained · pan and zoom remain available")
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .failure(let error):
                Text("Map preparation failed: \(error)").foregroundStyle(theme.colors.error)
            }
        }
    }

    private func handle(_ press: KeyPress) -> KeyPressResult {
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .character("q"): _ = requestTermination()
        case .space, .character(" "):
            scene = scene.next
            camera = scene.camera
        case .character("t"): appearance = appearance.next
        case .character("f"): fills.toggle()
        case .character("l"): labels.toggle()
        case .character("["): detail = detail.less
        case .character("]"): detail = detail.more
        case .character("d"): detail = detail.next
        case .character("r"): camera = scene.camera
        case .character("+"), .character("="): camera = try! camera.zoomed(by: 1 / 0.7)
        case .character("-"): camera = try! camera.zoomed(by: 0.7)
        case .arrowLeft: camera = try! camera.panned(longitudeFraction: -0.12, latitudeFraction: 0)
        case .arrowRight: camera = try! camera.panned(longitudeFraction: 0.12, latitudeFraction: 0)
        case .arrowUp: camera = try! camera.panned(longitudeFraction: 0, latitudeFraction: 0.12)
        case .arrowDown: camera = try! camera.panned(longitudeFraction: 0, latitudeFraction: -0.12)
        default: return .ignored
        }
        return .handled
    }
}

extension MapSpikeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ map spike · \(scene.title)")
            }.frame(height: 1, alignment: .leading)
            Text("\(sourceDescription) · detail \(detail.levelNumber)/\(MapDetail.allCases.count) \(detail.rawValue) · \(appearance.rawValue)")
                .foregroundStyle(theme.colors.mutedText).frame(height: 1, alignment: .leading)
            Spacer().frame(height: 1)
            mapView.frame(width: max(1, terminalSize.width - 2), height: viewport.rows, alignment: .center)
            Spacer().frame(height: 1)
            Text(String(format: "Center %.3f, %.3f · span %.4f°", camera.center.latitude,
                        camera.center.longitude, camera.longitudeSpan))
                .foregroundStyle(theme.colors.secondaryText).frame(height: 1, alignment: .leading)
            Text(source.metadata.attribution).foregroundStyle(theme.colors.mutedText).frame(height: 1, alignment: .leading)
            Text(licenseText).foregroundStyle(theme.colors.mutedText).frame(height: 1, alignment: .leading)
            Text(terminalSize.width >= 96
                 ? "↑↓←→ pan  +/- zoom  [ ] detail  d cycle  space map  t theme  f fill  l labels  r reset  q quit"
                 : terminalSize.width >= 58
                    ? "↑↓←→ pan  +/- zoom  [ ] detail  space map  q quit"
                    : "q quit  +/- zoom  space map")
                .foregroundStyle(theme.colors.accent).frame(height: 1, alignment: .leading)
        }
        .padding(1)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .topLeading)
        .focusable()
        .onKeyPress(perform: handle)
        .chioTheme(theme)
    }
}
