import Foundation
import SwiftTUIViews

/// A themed, north-up map with application-owned source, camera and marker selection.
///
/// Arrow keys pan; +/− zoom. N/P select the next/previous marker and centre it.
/// Return activates the selected marker. Tab leaves the map through native focus.
/// External camera and selection bindings remain authoritative, including unknown
/// selected IDs. External selection changes never move the camera implicitly.
/// Source loading and route calculation belong to the application.
@MainActor
public struct MapView {
    private let source: MapSource?
    private let camera: Binding<MapCamera>
    private let selection: Binding<String?>
    private let overlays: MapOverlays
    private let detail: MapDetail
    private let fills: Bool
    private let labels: Bool
    private let activation: @MainActor (MapMarker) -> Void
    private let viewportChange: @MainActor (MapViewport?) -> Void
    @Environment(\.chioTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    @State private var worker: MapPreparationWorker?
    @State private var completion: Completion?

    public init(source: MapSource, camera: Binding<MapCamera>, selection: Binding<String?> = .constant(nil),
                overlays: MapOverlays = .empty, detail: MapDetail = .minimal) {
        self.init(source: Optional(source), camera: camera, selection: selection, overlays: overlays, detail: detail)
    }

    /// A nil source means no geographic data has been loaded. Allocation, native
    /// focus, camera controls and marker selection remain available while the
    /// application acquires a source or presents its own loading/error status.
    public init(source: MapSource?, camera: Binding<MapCamera>, selection: Binding<String?> = .constant(nil),
                overlays: MapOverlays = .empty, detail: MapDetail = .minimal) {
        self.source = source
        self.camera = camera
        self.selection = selection
        self.overlays = overlays
        self.detail = detail
        fills = true
        labels = true
        activation = { _ in }
        viewportChange = { _ in }
    }

    private init(copying value: Self, fills: Bool? = nil, labels: Bool? = nil,
                 activation: (@MainActor (MapMarker) -> Void)? = nil,
                 viewportChange: (@MainActor (MapViewport?) -> Void)? = nil) {
        source = value.source
        camera = value.camera
        selection = value.selection
        overlays = value.overlays
        detail = value.detail
        self.fills = fills ?? value.fills
        self.labels = labels ?? value.labels
        self.activation = activation ?? value.activation
        self.viewportChange = viewportChange ?? value.viewportChange
        _theme = value._theme
        _enabled = value._enabled
        _focused = value._focused
        _worker = value._worker
        _completion = value._completion
    }

    /// Shows or hides polygon fills; route and geographic outlines remain visible.
    public func mapFills(_ visible: Bool) -> Self { Self(copying: self, fills: visible) }

    /// Shows background, route and unselected-marker labels. Selected-marker labels remain enabled.
    public func mapLabels(_ visible: Bool) -> Self { Self(copying: self, labels: visible) }

    /// Activation is explicit; merely selecting or replacing a source never calls it.
    public func onActivate(_ action: @escaping @MainActor (MapMarker) -> Void) -> Self {
        Self(copying: self, activation: action)
    }

    /// Reports the actual drawing allocation after layout, including its initial value.
    /// Nil means the compact fallback is visible. Pair a viewport with the current
    /// camera when explicitly requesting online tiles; observing never fetches data.
    public func onViewportChange(_ action: @escaping @MainActor (MapViewport?) -> Void) -> Self {
        Self(copying: self, viewportChange: action)
    }

    private func coverageNotice(camera: MapCamera, viewport: MapViewport?) -> String {
        guard let source else { return "" }
        let covered: Bool
        let unavailable: String
        switch source.coverage {
        case .tiled(let coverage):
            covered = viewport.map { coverage.covers(MapTileRequest(camera: camera, viewport: $0)) } ?? true
            unavailable = "Outside loaded coverage"
        default:
            covered = source.coverage.contains(camera.center)
            unavailable = "Outside offline coverage"
        }
        return covered
            ? "\(source.metadata.license) · \((source.metadata.attributionURL ?? source.metadata.licenseURL).absoluteString)"
            : "\(unavailable) · \(source.metadata.license)"
    }

    private struct Completion {
        let request: MapPreparationRequest
        let result: Result<PreparedMapDrawing, MapValidationError>
    }

    private func select(_ marker: MapMarker) {
        guard enabled else { return }
        selection.wrappedValue = marker.id
        // An application may reject a write. Do not pan to a rejected selection.
        guard selection.wrappedValue == marker.id else { return }
        let coordinate = try! MapCoordinate(latitude: min(MapLimits.mercatorLatitude,
                                             max(-MapLimits.mercatorLatitude, marker.coordinate.latitude)),
                                             longitude: marker.coordinate.longitude)
        camera.wrappedValue = try! MapCamera(center: coordinate, longitudeSpan: camera.wrappedValue.longitudeSpan)
    }

    private func stepMarker(_ direction: Int) {
        guard !overlays.markers.isEmpty else { return }
        let index: Int
        if let current = overlays.markers.firstIndex(where: { $0.id == selection.wrappedValue }) {
            index = (current + direction + overlays.markers.count) % overlays.markers.count
        } else {
            index = direction > 0 ? 0 : overlays.markers.count - 1
        }
        select(overlays.markers[index])
    }

    private func handle(_ press: KeyPress) -> KeyPressResult {
        guard enabled, press.modifiers.isEmpty else { return .ignored }
        // Bindings are read for each event, not captured at the preceding frame.
        switch press.key {
        case .arrowLeft: camera.wrappedValue = try! camera.wrappedValue.panned(longitudeFraction: -0.12, latitudeFraction: 0)
        case .arrowRight: camera.wrappedValue = try! camera.wrappedValue.panned(longitudeFraction: 0.12, latitudeFraction: 0)
        case .arrowUp: camera.wrappedValue = try! camera.wrappedValue.panned(longitudeFraction: 0, latitudeFraction: 0.12)
        case .arrowDown: camera.wrappedValue = try! camera.wrappedValue.panned(longitudeFraction: 0, latitudeFraction: -0.12)
        case .character("+"), .character("="): camera.wrappedValue = try! camera.wrappedValue.zoomed(by: 1 / 0.7)
        case .character("-"): camera.wrappedValue = try! camera.wrappedValue.zoomed(by: 0.7)
        case .character("n"): stepMarker(1)
        case .character("p"): stepMarker(-1)
        case .return:
            guard let marker = overlays.markers.first(where: { $0.id == selection.wrappedValue }) else { return .ignored }
            activation(marker)
        default: return .ignored
        }
        return .handled
    }

    @ViewBuilder
    private func drawing(_ prepared: PreparedMapDrawing, request: MapPreparationRequest) -> some View {
        let viewport = request.viewport
        let markers = MapMarkerPlacement(markers: overlays.markers, selection: selection.wrappedValue,
                                         camera: request.camera, viewport: viewport, showsLabels: labels)
        let routeNames = MapLabels(candidates: prepared.routeLabels, columns: viewport.columns, rows: viewport.rows,
                                   enabled: labels, detail: detail, reserved: markers.reservations)
        let names = MapLabels(candidates: prepared.map.labels, columns: viewport.columns, rows: viewport.rows,
                              enabled: labels, detail: detail, reserved: markers.reservations + routeNames.labels)
        ZStack(alignment: .topLeading) {
            Canvas(MapDrawing(prepared: prepared, colors: theme.colors,
                              waterColor: theme.map.water,
                              parkColor: theme.map.park), grid: .braille2x4)
            ForEach(names.labels, id: \.id) { label in
                Text(verbatim: label.text).lineLimit(1).foregroundStyle(theme.colors.foreground)
                    .background(theme.colors.surface)
                    .frame(width: label.width, height: 1, alignment: .leading).clipped()
                    .offset(x: label.column, y: label.row)
            }
            ForEach(routeNames.labels, id: \.id) { label in
                Text(verbatim: label.text).lineLimit(1).foregroundStyle(theme.colors.accent)
                    .background(theme.colors.surface)
                    .frame(width: label.width, height: 1, alignment: .leading).clipped()
                    .offset(x: label.column, y: label.row)
            }
            ForEach(markers.labels, id: \.id) { label in
                Text(verbatim: label.text).lineLimit(1)
                    .foregroundStyle(label.id == selection.wrappedValue ? theme.colors.accent : theme.colors.foreground)
                    .background(theme.colors.surface)
                    .frame(width: label.width, height: 1, alignment: .leading).clipped()
                    .offset(x: label.column, y: label.row)
            }
            ForEach(markers.markers, id: \.value.id) { marker in
                Text(marker.selected ? "◆" : "●")
                    .foregroundStyle(marker.selected ? theme.colors.accent : theme.colors.foreground)
                    .background(theme.colors.surface)
                    .frame(width: 1, height: 1)
                    .offset(x: marker.column, y: marker.row)
                    .onTapGesture { select(marker.value); focused = true }
                    .accessibilityLabel(marker.value.title.isEmpty ? marker.value.id : marker.value.title)
            }
        }
        .frame(width: viewport.columns, height: viewport.rows, alignment: .topLeading)
        .clipped()
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).bold().foregroundStyle(theme.colors.accent)
            if let marker = overlays.markers.first(where: { $0.id == selection.wrappedValue }) {
                Text(marker.title.isEmpty ? marker.id : marker.title)
            }
            Text(detail).foregroundStyle(theme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
    }

    @ViewBuilder
    private func content(_ request: MapPreparationRequest?, small: Bool) -> some View {
        if small {
            message("More room for the map", detail: "Camera and selection retained · Resize to continue")
        } else if source == nil {
            message("No map source loaded", detail: "Pan and zoom remain available")
        } else if let request, let completion, completion.request == request {
            switch completion.result {
            case .success(let prepared): drawing(prepared, request: request)
            case .failure:
                message("Too much map detail", detail: "Try another scale, lower detail, or turn off fills.")
            }
        } else {
            message("Preparing map…", detail: "Pan and zoom remain available")
        }
    }
}

extension MapView: View {
    public var body: some View {
        GeometryReader { geometry in
            let current = camera.wrappedValue
            let viewport = MapViewport.fitting(width: geometry.size.width, height: geometry.size.height,
                cellAspectRatio: geometry.cellPixelMetrics.aspectRatio, camera: current)
            let request = source.flatMap { source in
                viewport.map { MapPreparationRequest(dataset: source.dataset, camera: current,
                    viewport: $0, detail: detail, routes: overlays.routes, fills: fills) }
            }
            VStack(alignment: .leading, spacing: 0) {
                content(request, small: viewport == nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                HStack(spacing: 1) {
                    Text(focused ? "›" : " ").foregroundStyle(theme.colors.accent)
                    Text(source?.metadata.attribution ?? "").foregroundStyle(theme.colors.mutedText)
                }.frame(height: 1, alignment: .leading).clipped()
                Text(coverageNotice(camera: current, viewport: viewport))
                    .foregroundStyle(theme.colors.mutedText).frame(height: 1, alignment: .leading).clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .onChange(of: viewport, initial: true) { _, value in viewportChange(value) }
            .task(id: request) {
                guard let request else { completion = nil; return }
                // Construct resources after mounting, so separate mounts own separate workers.
                let owner: MapPreparationWorker
                if let worker { owner = worker } else {
                    owner = MapPreparationWorker()
                    worker = owner
                }
                do {
                    let prepared = try await owner.prepare(request)
                    guard !Task.isCancelled, camera.wrappedValue == request.camera else { return }
                    completion = Completion(request: request, result: .success(prepared))
                } catch is CancellationError {
                    // Cancelled requests never replace a newer completion.
                } catch {
                    guard !Task.isCancelled, camera.wrappedValue == request.camera else { return }
                    completion = Completion(request: request, result: .failure(error as? MapValidationError ?? .budgetExceeded))
                }
            }
        }
        .background(theme.colors.surface)
        .foregroundStyle(theme.colors.foreground)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(perform: handle)
        .accessibilityLabel("Map\(overlays.markers.first(where: { $0.id == selection.wrappedValue }).map { ", selected \($0.title.isEmpty ? $0.id : $0.title)" } ?? "")")
        .accessibilityHint("Arrows pan, plus and minus zoom, n and p select places, Return opens, Tab leaves the map")
    }
}
