import Chio
import Foundation
import SwiftTUI

/// The application owns its map choice, annotations and bound interaction state.
@MainActor
struct MapExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var scene: MapFixtures.Scene
    @State private var camera: MapCamera
    @State private var selection: String?
    @State private var appearance: MapExampleCommand.Appearance
    @State private var fills = true
    @State private var labels = true
    @State private var detail: MapDetail
    @State private var activation = "Return opens the selected place"
    @State private var retry = 0
    private let fixtures: MapFixtures
    private let streetSource: MapFixtures.StreetSource
    private let acquisition: MapExampleAcquisition

    init(fixtures: MapFixtures, scene: MapFixtures.Scene, appearance: MapExampleCommand.Appearance,
         detail: MapDetail = .minimal,
         streetSource: MapFixtures.StreetSource = .overpass, acquisition: MapExampleAcquisition = .offline) {
        self.fixtures = fixtures
        self.streetSource = streetSource
        self.acquisition = acquisition
        _scene = State(wrappedValue: scene)
        _camera = State(wrappedValue: scene.camera)
        _selection = State(wrappedValue: nil)
        _appearance = State(wrappedValue: appearance)
        _detail = State(wrappedValue: detail)
    }

    private var theme: ChioTheme { appearance.theme }
    private var source: MapSource { fixtures.source(for: scene, streetSource: streetSource) }
    private var overlays: MapOverlays { scene.overlays }
    private var selectedTitle: String {
        overlays.markers.first(where: { $0.id == selection })?.title ?? "None"
    }
    private var context: String {
        if acquisition.isOnline { return "Online · \(detail.levelNumber)/\(MapDetail.allCases.count) \(detail.rawValue) · \(appearance.rawValue) · synthetic guide" }
        let sourceTitle = scene == .world ? "Natural Earth" : streetSource.title
        return "Offline · \(sourceTitle) · \(detail.levelNumber)/\(MapDetail.allCases.count) \(detail.rawValue) · \(appearance.rawValue) · synthetic guide"
    }

    /// MapView handles pan, zoom, marker traversal and activation through native focus.
    private func handle(_ press: KeyPress) -> KeyPressResult {
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .character("q"): _ = requestTermination()
        case .space, .character(" "):
            scene = scene.next
            camera = scene.camera
            selection = nil
            activation = "Return opens the selected place"
        case .character("t"): appearance = appearance.next
        case .character("["): detail = detail.less
        case .character("]"): detail = detail.more
        case .character("d"): detail = detail.next
        case .character("f"): fills.toggle()
        case .character("l"): labels.toggle()
        case .character("r"): camera = scene.camera
        case .character("e") where acquisition.isOnline: retry &+= 1
        default: return .ignored
        }
        return .handled
    }
}

extension MapExampleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ maps · \(scene.title)")
            }.frame(height: 1, alignment: .leading)
            Text(context).foregroundStyle(theme.colors.mutedText)
                .frame(height: 1, alignment: .leading)
            if acquisition.isOnline {
                OnlineMapContent(camera: $camera,
                    selection: $selection, overlays: overlays, detail: detail, fills: fills,
                    labels: labels, retry: retry, activate: { activation = "Opened \($0.title)" },
                    makeLoader: { try await acquisition.makeLoader() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MapView(source: source, camera: $camera, selection: $selection,
                        overlays: overlays, detail: detail)
                    .mapFills(fills)
                    .mapLabels(labels)
                    .onActivate { marker in activation = "Opened \(marker.title)" }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(String(format: "Center %.3f, %.3f · span %.4f°", camera.center.latitude,
                        camera.center.longitude, camera.longitudeSpan))
                .foregroundStyle(theme.colors.secondaryText)
                .frame(height: 1, alignment: .leading)
            Text("Selected: \(selectedTitle) · \(activation)")
                .foregroundStyle(theme.colors.secondaryText)
                .frame(height: 1, alignment: .leading)
            Text(terminalSize.width >= 80
                 ? "↑↓←→ pan  +/- zoom  n/p place  Return open  space map  q quit"
                 : "q quit  space map  n/p place")
                .foregroundStyle(theme.colors.accent)
                .frame(height: 1, alignment: .leading)
            Text(terminalSize.width >= 80
                 ? "[] detail  d cycle  t theme  f fills  l labels  r reset  space map"
                 : "[] detail  t theme  r reset")
                .foregroundStyle(theme.colors.mutedText)
                .frame(height: 1, alignment: .leading)
        }
        .padding(1)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .topLeading)
        .onKeyPress(perform: handle)
        .chioTheme(theme)
    }
}
