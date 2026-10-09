import Chio
import Foundation
import SwiftTUI

/// Owns hosted capture and measurement effects without reaching into map internals.
@MainActor
enum MapCapture {
    struct CapturedFrame {
        let raster: RasterSurface
        /// Session construction, startup, preparation and delivery of the first completed UI frame.
        let firstFrameMS: Double
    }

    static func snapshot(fixtures: MapFixtures, scene: MapFixtures.Scene,
                         appearance: MapExampleCommand.Appearance, width: Int, height: Int,
                         cellAspect: Double? = nil, detail: MapDetail = .minimal,
                         streetSource: MapFixtures.StreetSource = .overpass) async throws -> CapturedFrame {
        let recorder = FrameRecorder(size: CellSize(width: width, height: height))
        let surface = HostedRasterSurface(surfaceSize: .init(width: width, height: height),
                                          appearance: .fallback, onFrame: { recorder.receive($0) })
        let app = MapExampleApplication(fixtures: fixtures, scene: scene, appearance: appearance,
                                        cellAspect: cellAspect, detail: detail, streetSource: streetSource)
        let session = try HostedSceneSession(for: app, sceneID: WindowIdentifier("Chio maps"), surface: surface)
        let run = Task {
            do {
                let reason = try await session.start()
                recorder.stopped()
                return reason
            } catch {
                recorder.failed(error)
                throw error
            }
        }

        let result: Result<CapturedFrame, any Error>
        do { result = .success(try await recorder.wait()) }
        catch { result = .failure(error) }
        // Always stop and join the session, including timeout and cancellation paths.
        session.stop()
        let termination = await run.result
        let capture = try result.get()
        _ = try termination.get()
        return capture
    }

    /// One warm-up and three measured fresh sessions per scene and terminal size.
    /// Small sizes measure the component's compact summary. Fixture I/O is excluded.
    static func benchmark(fixtures: MapFixtures, appearance: MapExampleCommand.Appearance,
                          cellAspect: Double? = nil, detail: MapDetail = .minimal,
                          streetSource: MapFixtures.StreetSource = .overpass) async throws {
        var results: [Measurement] = []
        for scene in MapFixtures.Scene.allCases {
            for (width, height) in [(100, 30), (60, 20), (36, 18)] {
                var times: [Double] = []
                for sample in 0..<4 {
                    let capture = try await snapshot(fixtures: fixtures, scene: scene, appearance: appearance,
                                                     width: width, height: height, cellAspect: cellAspect,
                                                     detail: detail, streetSource: streetSource)
                    if sample > 0 { times.append(capture.firstFrameMS) }
                }
                results.append(Measurement(scene: scene.rawValue,
                                           source: scene == .world ? "natural-earth" : streetSource.rawValue,
                                           detail: detail, width: width, height: height,
                                           cellAspect: cellAspect ?? 2,
                                           warmupSamples: 1, measuredSamples: times.count,
                                           firstFrameMedianMS: times.sorted()[times.count / 2],
                                           firstFrameMaxMS: times.max()!))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(results), as: UTF8.self))
    }

    /// Retains the existing per-cell JSON interchange used by render-snapshot.py.
    static func export(_ raster: RasterSurface, background: Color, foreground: Color) throws {
        let cells = raster.cells.map { row in
            row.map { cell in
                Pixel(character: String(cell.character), foreground: cell.style?.foregroundColor ?? foreground,
                      background: cell.style?.backgroundColor ?? background)
            }
        }
        print(String(decoding: try JSONEncoder().encode(cells), as: UTF8.self))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// An explicit live recorder retains only the first complete frame.
    @MainActor
    private final class FrameRecorder {
        private let size: CellSize
        private let clock = ContinuousClock()
        private let began = ContinuousClock.now
        private var completed: CapturedFrame?
        private var failure: (any Error)?

        init(size: CellSize) { self.size = size }

        func receive(_ frame: SemanticHostFrame) {
            guard completed == nil, failure == nil, frame.raster.size == size else { return }
            let text = frame.raster.lines.joined(separator: "\n")
            // The app header must exist, and asynchronous preparation must have finished.
            // Below-minimum summaries count as a completed, valid presentation.
            guard text.contains("chio"), text.contains("/ maps"),
                  !text.contains("Preparing map") else { return }
            completed = CapturedFrame(raster: frame.raster,
                                      firstFrameMS: MapCapture.milliseconds(began.duration(to: clock.now)))
        }

        func failed(_ error: any Error) { failure = error }

        func stopped() {
            if completed == nil, failure == nil { failure = CaptureError.stoppedBeforeFrame }
        }

        func wait() async throws -> CapturedFrame {
            let deadline = began.advanced(by: .seconds(10))
            while clock.now < deadline {
                try Task.checkCancellation()
                if let failure { throw failure }
                if let completed { return completed }
                try await Task.sleep(for: .milliseconds(5))
            }
            throw CaptureError.frameTimeout
        }
    }

    private enum CaptureError: Error, CustomStringConvertible {
        case frameTimeout
        case stoppedBeforeFrame

        var description: String {
            switch self {
            case .frameTimeout: "Timed out after 10 seconds waiting for a completed hosted map frame."
            case .stoppedBeforeFrame: "The hosted map session stopped before delivering a completed frame."
            }
        }
    }

    private struct Pixel: Encodable {
        let character: String
        let foreground: Color
        let background: Color
    }

    private struct Measurement: Encodable {
        let scene: String
        let source: String
        let detail: MapDetail
        let width: Int
        let height: Int
        let cellAspect: Double
        let warmupSamples: Int
        let measuredSamples: Int
        let firstFrameMedianMS: Double
        let firstFrameMaxMS: Double
    }
}
