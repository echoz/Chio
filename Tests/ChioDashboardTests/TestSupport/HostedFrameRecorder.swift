import SwiftTUIRuntime

/// Records the runtime's public host frames without reading application storage.
@MainActor
final class HostedFrameRecorder {
    private var latest: SemanticHostFrame?
    private var pending: PendingWait?
    private var deadline: Task<Void, Never>?
    private let started = ContinuousClock.now
    private var recentFrames: [String] = []

    func receive(_ frame: SemanticHostFrame) {
        let routes = frame.semantics.scrollRoutes.map {
            "offset=\($0.contentOffset), viewport=\($0.viewportRect.size), content=\($0.contentBounds.size)"
        }.joined(separator: "; ")
        recentFrames.append("#\(frame.sequence) at \(started.duration(to: .now)): \(routes)")
        if recentFrames.count > 8 { recentFrames.removeFirst() }
        latest = frame
        guard let pending, pending.matches(frame) else { return }
        self.pending = nil
        deadline?.cancel()
        deadline = nil
        pending.continuation.resume(returning: frame)
    }

    func wait(after sequence: UInt64? = nil, description: String,
              matching predicate: @escaping @MainActor (SemanticHostFrame) -> Bool) async throws -> SemanticHostFrame {
        let matches: @MainActor (SemanticHostFrame) -> Bool = { frame in
            (sequence == nil || frame.sequence > sequence!) && predicate(frame)
        }
        if let latest, matches(latest) { return latest }
        precondition(pending == nil)
        return try await withCheckedThrowingContinuation { continuation in
            pending = PendingWait(matches: matches, continuation: continuation)
            deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                guard let self, let pending = self.pending else { return }
                self.pending = nil
                self.deadline = nil
                let focus = self.latest?.focusedIdentity
                let focusedNode = self.latest?.semantics.accessibilityNodes.first { $0.identity == focus }
                pending.continuation.resume(throwing: FrameTimeout(
                    expectation: description,
                    frames: recentFrames.joined(separator: "\n"),
                    focus: "\(String(describing: focusedNode?.role)) / \(focusedNode?.label ?? "unlabeled") / \(String(describing: focus))",
                    raster: self.latest?.raster.lines.joined(separator: "\n") ?? "No frame received"
                ))
            }
        }
    }

    private struct PendingWait {
        let matches: @MainActor (SemanticHostFrame) -> Bool
        let continuation: CheckedContinuation<SemanticHostFrame, any Error>
    }

    private struct FrameTimeout: Error, CustomStringConvertible {
        let expectation: String
        let frames: String
        let focus: String
        let raster: String
        var description: String {
            "Timed out waiting for \(expectation). Focus: \(focus). Recent frames:\n\(frames)\nRaster:\n\(raster)"
        }
    }
}
