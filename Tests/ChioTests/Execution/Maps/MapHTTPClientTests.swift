@testable import Chio
import Dispatch
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct MapHTTPClientTests {
    @Test("Real localhost transport bounds decompressed bodies and rejects HTTP/MIME/redirect failures")
    func boundedHTTP() async throws {
        let server = try await Server()
        defer { server.stop() }
        let valid = try await bounded("empty HTTP 200") { try await MapHTTPClient.fetch(server.url("/empty"), resource: .tile) }
        #expect(valid.data.isEmpty)
        #expect(valid.headers["cache-control"] == "max-age=60")
        let tile = try await bounded("nonempty HTTP 200") { try await MapHTTPClient.fetch(server.url("/tile"), resource: .tile) }
        #expect(tile.data == Data([0x08, 0x00]))
        let redirected = try await bounded("permitted same-origin redirect") { try await MapHTTPClient.fetch(server.url("/redirect"), resource: .tile) }
        #expect(redirected.data.isEmpty)
        for (path, expected) in [
            ("/status", MapTileLoader.LoadingError.httpStatus(503)),
            ("/mime", .unexpectedContentType), ("/cross-host", .rejectedRedirect),
            ("/scheme", .rejectedRedirect), ("/loop", .rejectedRedirect),
            ("/oversize-header", .responseTooLarge), ("/oversize-stream", .responseTooLarge),
        ] {
            let terminalCount = Mutex(0)
            await #expect(throws: expected) {
                try await bounded("reject \(path)") {
                    try await MapHTTPClient.fetch(server.url(path), resource: .tile,
                        onTerminalAcknowledgement: { terminalCount.withLock { $0 += 1 } })
                }
            }
            #expect(terminalCount.withLock { $0 } == 1)
        }
        // The compressed Content-Length is below the catalog limit, while the
        // decompressed delegate bytes exceed it. This is real URLSession gzip.
        await #expect(throws: MapTileLoader.LoadingError.responseTooLarge) {
            try await bounded("decompressed catalog overflow") { try await MapHTTPClient.fetch(server.url("/gzip"), resource: .catalog) }
        }
        let terminalCount = Mutex(0)
        let pending = Task {
            try await MapHTTPClient.fetch(server.url("/slow"), resource: .tile,
                onTerminalAcknowledgement: { terminalCount.withLock { $0 += 1 } })
        }
        defer { pending.cancel() }
        try await bounded("slow fixture request entered") {
            while true {
                let status = try await MapHTTPClient.fetch(server.url("/started"), resource: .catalog)
                if String(data: status.data, encoding: .utf8) == "true" { return }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await bounded("in-flight cancellation acknowledgment") { try await pending.value } }
        #expect(terminalCount.withLock { $0 } == 1)
        do {
            _ = try await bounded("native resource timeout") { try await MapHTTPClient.fetch(server.url("/slow"), resource: .tile, timeout: 0.2) }
            Issue.record("Slow HTTP resource did not time out")
        } catch let error as URLError { #expect(error.code == .timedOut) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MapHTTPClient.fetch(server.url("/empty"), resource: .tile)
        }
        await #expect(throws: CancellationError.self) { try await bounded("cancel before registration") { try await cancelled.value } }
    }

    @Test("Cancellation queued before a redirect decision still acknowledges exactly once")
    func cancelledPendingRedirect() async throws {
        let server = try await Server()
        defer { server.stop() }
        let control = RedirectGate()
        let acknowledgments = Mutex(0)
        let pending = Task {
            try await MapHTTPClient.fetch(server.url("/redirect"), resource: .tile,
                onTerminalAcknowledgement: { acknowledgments.withLock { $0 += 1 } },
                beforeRedirectDecision: { control.intercept($0) })
        }
        defer { pending.cancel(); control.release() }
        try await bounded("redirect callback entered") {
            while !control.entered { try await Task.sleep(for: .milliseconds(1)) }
        }
        pending.cancel()
        // Observe the real Foundation task state, not a timed guess that caller
        // cancellation has reached the transport. The decision remains withheld.
        try await bounded("real pending-redirect transport cancellation") {
            while !control.transportCancelled { try await Task.sleep(for: .milliseconds(1)) }
        }
        control.release()
        await #expect(throws: CancellationError.self) {
            try await bounded("pending-redirect terminal acknowledgment") { try await pending.value }
        }
        #expect(acknowledgments.withLock { $0 } == 1)
    }

    @Test("Same-origin redirects normalize implicit HTTP and HTTPS ports")
    func originComparison() {
        #expect(MapHTTPClient.sameOrigin(URL(string: "https://example.test/a")!, URL(string: "https://example.test:443/b")!))
        #expect(MapHTTPClient.sameOrigin(URL(string: "http://example.test/a")!, URL(string: "http://example.test:80/b")!))
        #expect(!MapHTTPClient.sameOrigin(URL(string: "http://example.test/a")!, URL(string: "https://example.test/b")!))
        #expect(!MapHTTPClient.sameOrigin(URL(string: "https://example.test/a")!, URL(string: "https://example.test:444/b")!))
    }

    @Test("Discovery chooses the first checked HTTPS OpenFreeMap template and retains observed provenance")
    func discovery() async throws {
        let catalog = Data(#"{"tiles":["https://other.test/{z}/{x}/{y}.pbf","https://tiles.openfreemap.org/bad\n/{z}/{x}/{y}.pbf","https://tiles.openfreemap.org/planet/observed/{z}/{x}/{y}.pbf"],"minzoom":0,"maxzoom":14}"#.utf8)
        let source = try await OpenMapTilesSource.fetchOpenFreeMap { url, resource in
            #expect(url.absoluteString == "https://tiles.openfreemap.org/planet")
            #expect(resource == .catalog)
            return .init(data: catalog, headers: [:])
        }
        #expect(source.zoomRange == 0...14)
        #expect(source.metadata.sourceRevision == source.template)
        #expect(source.metadata.attribution.contains("OpenStreetMap"))
        #expect(source.metadata.license == "ODbL")
        for bad in [#"{"tiles":["http://tiles.openfreemap.org/{z}/{x}/{y}.pbf"],"minzoom":0,"maxzoom":14}"#,
                    #"{"tiles":["https://tiles.openfreemap.org/{z}/{x}/{y}.pbf"],"minzoom":15,"maxzoom":14}"#,
                    #"{"tiles":[],"minzoom":0,"maxzoom":14}"#, "garbage"] {
            await #expect(throws: MapTileLoader.LoadingError.invalidCatalog) {
                try await OpenMapTilesSource.fetchOpenFreeMap { _, _ in .init(data: Data(bad.utf8), headers: [:]) }
            }
        }
    }

    private func bounded<T: Sendable>(_ phase: String, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask { try await Task.sleep(for: .seconds(5)); throw WaitError.timeout(phase) }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
    private enum WaitError: Error { case timeout(String), fixtureStartup(String) }

    private final class RedirectGate: Sendable {
        private let task = Mutex<URLSessionTask?>(nil)
        private let releaseSignal = DispatchSemaphore(value: 0)
        var entered: Bool { task.withLock { $0 != nil } }
        var transportCancelled: Bool {
            task.withLock { $0?.state == .canceling || $0?.state == .completed }
        }
        func intercept(_ task: URLSessionTask) {
            self.task.withLock { $0 = task }
            if releaseSignal.wait(timeout: .now() + 5) != .success {
                Issue.record("Pending redirect fixture was not released within five seconds")
            }
        }
        func release() { releaseSignal.signal() }
    }

    /// Sole test owner of a localhost subprocess. Startup and teardown are bounded;
    /// handlers use daemon threads so disconnected clients cannot retain the child.
    private final class Server: @unchecked Sendable {
        private let process: Process
        private let base: URL
        private let errorHandle: FileHandle
        private let stopped = Mutex(false)
        init() async throws {
            try Task.checkCancellation()
            let process = Process(), pipe = Pipe(), errorPipe = Pipe()
            let errors = Mutex(Data())
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-u", "-c", Self.script]
            process.standardOutput = pipe
            process.standardError = errorPipe
            let command = "executable=/usr/bin/env; arguments=\(process.arguments!.debugDescription)"
            let handle = pipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            for input in [handle, errorHandle] {
                let flags = fcntl(input.fileDescriptor, F_GETFL)
                guard flags >= 0 else { throw WaitError.fixtureStartup("Could not read fixture pipe flags; \(command)") }
                let hasNonblockingPipe = fcntl(input.fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0
                guard hasNonblockingPipe else { throw WaitError.fixtureStartup("Could not make fixture pipe nonblocking; \(command)") }
            }
            do { try process.run() }
            catch { throw WaitError.fixtureStartup("Could not launch fixed Python HTTP fixture: \(error); \(command)") }
            errorHandle.readabilityHandler = { handle in
                guard let chunk = Self.readAvailable(from: handle, limit: 1_024) else { return }
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                errors.withLock { bytes in bytes.append(chunk.prefix(max(0, 8_192 - bytes.count))) }
            }
            let output = Mutex((bytes: Data(), isComplete: false))
            handle.readabilityHandler = { handle in
                guard let chunk = Self.readAvailable(from: handle, limit: 256) else { return }
                let isComplete = output.withLock { state in
                    state.bytes.append(chunk.prefix(max(0, 256 - state.bytes.count)))
                    let hasNewline = state.bytes.contains(10)
                    let hasReachedLimit = state.bytes.count == 256
                    state.isComplete = chunk.isEmpty || hasNewline || hasReachedLimit
                    return state.isComplete
                }
                if isComplete { handle.readabilityHandler = nil }
            }
            defer { handle.readabilityHandler = nil; try? handle.close() }
            do {
                // Yield the cooperative executor while Foundation dispatches pipe
                // readiness. No reader thread blocks waiting for the child output.
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(5))
                while !output.withLock({ $0.isComplete }) {
                    try Task.checkCancellation()
                    guard clock.now < deadline else { throw WaitError.timeout("Python HTTP fixture readiness after five seconds") }
                    try await Task.sleep(for: .milliseconds(10))
                }
                try Task.checkCancellation()
                let data = output.withLock { $0.bytes }
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: text) else { throw WaitError.fixtureStartup("Invalid readiness URL") }
                let isLocalhost = url.host == "127.0.0.1"
                guard isLocalhost else { throw WaitError.fixtureStartup("Readiness URL is not the localhost fixture") }
                self.process = process
                self.base = url
                self.errorHandle = errorHandle
            } catch {
                let status: String
                if process.isRunning { status = "still running" }
                else { status = "exited \(process.terminationStatus)" }
                Self.terminate(process)
                errorHandle.readabilityHandler = nil
                try? errorHandle.close()
                if error is CancellationError { throw error }
                let stdout = output.withLock { String(decoding: $0.bytes, as: UTF8.self) }
                let stderr = errors.withLock { String(decoding: $0, as: UTF8.self) }
                throw WaitError.fixtureStartup("Python HTTP fixture startup failed: \(error); child \(status); \(command); stdout=\(stdout.debugDescription); stderr=\(stderr.debugDescription)")
            }
        }
        func url(_ path: String) -> URL { URL(string: path, relativeTo: base)!.absoluteURL }
        func stop() {
            let shouldStop = stopped.withLock { value in if value { return false }; value = true; return true }
            if shouldStop {
                Self.terminate(process)
                errorHandle.readabilityHandler = nil
                try? errorHandle.close()
            }
        }
        deinit { stop() }
        private static func readAvailable(from handle: FileHandle, limit: Int) -> Data? {
            // One nonblocking POSIX read cannot wait to fill a Foundation read's
            // requested length. A transient read error waits for the next event.
            var bytes = [UInt8](repeating: 0, count: limit)
            let count = bytes.withUnsafeMutableBytes { buffer in
                read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
            }
            guard count >= 0 else { return nil }
            return Data(bytes.prefix(count))
        }
        private static func terminate(_ process: Process) {
            if process.isRunning { process.terminate() }
            let exited = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { process.waitUntilExit(); exited.signal() }
            if exited.wait(timeout: .now() + 3) != .success {
                _ = kill(process.processIdentifier, SIGKILL)
                if exited.wait(timeout: .now() + 2) != .success { Issue.record("Local HTTP fixture failed to exit within five seconds") }
            }
        }
        private static let script = #"""
import sys
print('fixture: entered; python=%s' % sys.executable, file=sys.stderr, flush=True)
import gzip, http.server, socketserver, threading, time
print('fixture: imports complete', file=sys.stderr, flush=True)
started = threading.Event()
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path = self.path
        if path in ('/redirect', '/cross-host', '/scheme', '/loop'):
            location = {'/redirect':'/empty', '/loop':'/loop', '/cross-host':'http://localhost:%s/empty' % self.server.server_port, '/scheme':'https://127.0.0.1:%s/empty' % self.server.server_port}[path]
            self.send_response(302); self.send_header('Location', location); self.send_header('Content-Length','0'); self.end_headers(); return
        if path == '/oversize-header':
            self.send_response(200); self.send_header('Content-Type','application/octet-stream'); self.send_header('Content-Length',str(16*1024*1024+1)); self.end_headers(); return
        if path == '/oversize-stream':
            self.send_response(200); self.send_header('Content-Type','application/octet-stream'); self.end_headers()
            try:
                for i in range(257): self.wfile.write(b'\0'*65536); self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError): pass
            return
        if path == '/gzip':
            body = gzip.compress(b' '* (256*1024+1))
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Encoding','gzip'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body); return
        body = b'\x08\x00' if path == '/tile' else b''
        if path == '/started': body = b'true' if started.is_set() else b'false'
        self.send_response(503 if path == '/status' else 200)
        self.send_header('Content-Type','text/html' if path == '/mime' else ('application/json' if path == '/started' else 'application/octet-stream'))
        self.send_header('Cache-Control','max-age=60')
        self.send_header('Content-Length',str(1 if path == '/slow' else len(body))); self.end_headers()
        if path == '/slow': started.set(); time.sleep(4); body = b'x'
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    def server_bind(self):
        # HTTPServer otherwise reverse-resolves even numeric loopback. This
        # fixture needs the bound address and port, with no DNS dependency.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]
print('fixture: binding numeric loopback', file=sys.stderr, flush=True)
server = Server(('127.0.0.1',0), Handler)
print('fixture: ready', file=sys.stderr, flush=True)
print('http://127.0.0.1:%s/' % server.server_port, flush=True)
server.serve_forever()
"""#
    }
}
