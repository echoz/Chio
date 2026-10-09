import Chio
import SwiftTUI

/// The example explicitly owns discovery, acquisition and the last accepted source.
/// MapView remains the same native focus target through every loading state.
@MainActor
struct OnlineMapContent {
    private let fallback: MapSource
    private let camera: Binding<MapCamera>
    private let selection: Binding<String?>
    private let overlays: MapOverlays
    private let detail: MapDetail
    private let fills: Bool
    private let labels: Bool
    private let retry: Int
    private let activate: @MainActor (MapMarker) -> Void
    private let makeLoader: @Sendable () async throws -> MapTileLoader
    @Environment(\.chioTheme) private var theme
    @State private var viewport: MapViewport?
    @State private var loader: MapTileLoader?
    @State private var snapshot: MapTileSnapshot?
    @State private var update: Update = .idle

    init(fallback: MapSource, camera: Binding<MapCamera>, selection: Binding<String?>,
         overlays: MapOverlays, detail: MapDetail, fills: Bool, labels: Bool, retry: Int,
         activate: @escaping @MainActor (MapMarker) -> Void,
         makeLoader: @escaping @Sendable () async throws -> MapTileLoader = {
             MapTileLoader(source: try await OpenMapTilesSource.fetchOpenFreeMap())
         }) {
        self.fallback = fallback
        self.camera = camera
        self.selection = selection
        self.overlays = overlays
        self.detail = detail
        self.fills = fills
        self.labels = labels
        self.retry = retry
        self.activate = activate
        self.makeLoader = makeLoader
    }

    private enum Update {
        case idle
        case loading(MapTileRequest)
        case failed(MapTileRequest)
    }

    private struct Work: Hashable {
        let request: MapTileRequest?
        let retry: Int
    }

    // This is the example's acquisition policy, independent of Chio's visual detail.
    private var worldOverview: Bool { camera.wrappedValue.longitudeSpan >= 45 }
    private var request: MapTileRequest? {
        worldOverview ? nil : viewport.map { MapTileRequest(camera: camera.wrappedValue, viewport: $0) }
    }
    private var source: MapSource { worldOverview ? fallback : snapshot?.source ?? fallback }
    private var status: String {
        if worldOverview { return "World overview · bundled Natural Earth · zoom in for online tiles" }
        guard let request else { return "Online paused · resize to load tiles" }
        let retained = snapshot == nil ? "bundled overview" : "previous coverage"
        switch update {
        case .failed(let failed) where failed == request:
            return "Could not load this area · showing \(retained) · e retry"
        case .loading(let pending) where pending == request:
            return "Loading tiles… · showing \(retained)"
        default:
            guard let snapshot, snapshot.request == request else {
                return "Loading tiles… · showing \(retained)"
            }
            let resolution = snapshot.attainedZoom < snapshot.requestedZoom
                ? " · reduced from z\(snapshot.requestedZoom) to fit geometry limits" : ""
            return "Online · z\(snapshot.attainedZoom)\(resolution) · e retry"
        }
    }

    private func load(_ work: Work) async {
        guard let requested = work.request else { update = .idle; return }
        update = .loading(requested)
        do {
            // Coalesce rapid native key events without delaying camera feedback.
            try await Task.sleep(for: .milliseconds(150))
            let owner: MapTileLoader
            if let loader { owner = loader } else {
                owner = try await makeLoader()
                try Task.checkCancellation()
                loader = owner
            }
            let loaded = try await owner.load(requested)
            guard !Task.isCancelled, request == requested else { return }
            snapshot = loaded
            update = .idle
        } catch is CancellationError {
            // A replaced request cannot publish over its successor.
        } catch {
            guard !Task.isCancelled, request == requested else { return }
            update = .failed(requested)
        }
    }
}

extension OnlineMapContent: View {
    var body: some View {
        let work = Work(request: request, retry: retry)
        VStack(alignment: .leading, spacing: 0) {
            MapView(source: source, camera: camera, selection: selection, overlays: overlays, detail: detail)
                .mapFills(fills)
                .mapLabels(labels)
                .onActivate(activate)
                .onViewportChange { viewport = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(status).foregroundStyle(theme.colors.secondaryText)
                .frame(height: 1, alignment: .leading).clipped()
        }
        .task(id: work) { await load(work) }
    }
}
