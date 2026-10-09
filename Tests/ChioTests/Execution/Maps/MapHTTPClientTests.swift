@testable import Chio
import Dispatch
import Foundation
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
        let server = try Server()
        defer { server.stop() }
        let valid = try await MapHTTPClient.fetch(server.url("/empty"), resource: .tile)
        #expect(valid.data.isEmpty)
        #expect(valid.headers["cache-control"] == "max-age=60")
        let tile = try await MapHTTPClient.fetch(server.url("/tile"), resource: .tile)
        #expect(tile.data == Data([0x08, 0x00]))
        let redirected = try await MapHTTPClient.fetch(server.url("/redirect"), resource: .tile)
        #expect(redirected.data.isEmpty)
        for (path, expected) in [
            ("/status", MapTileLoader.LoadingError.httpStatus(503)),
            ("/mime", .unexpectedContentType), ("/cross-host", .rejectedRedirect),
            ("/scheme", .rejectedRedirect), ("/loop", .rejectedRedirect),
            ("/oversize-header", .responseTooLarge), ("/oversize-stream", .responseTooLarge),
        ] {
            let terminalCount = Mutex(0)
            await #expect(throws: expected) {
                try await bounded {
                    try await MapHTTPClient.fetch(server.url(path), resource: .tile,
                        onTerminalAcknowledgement: { terminalCount.withLock { $0 += 1 } })
                }
            }
            #expect(terminalCount.withLock { $0 } == 1)
        }
        // The compressed Content-Length is below the catalog limit, while the
        // decompressed delegate bytes exceed it. This is real URLSession gzip.
        await #expect(throws: MapTileLoader.LoadingError.responseTooLarge) {
            try await bounded { try await MapHTTPClient.fetch(server.url("/gzip"), resource: .catalog) }
        }
        let terminalCount = Mutex(0)
        let pending = Task {
            try await MapHTTPClient.fetch(server.url("/slow"), resource: .tile,
                onTerminalAcknowledgement: { terminalCount.withLock { $0 += 1 } })
        }
        defer { pending.cancel() }
        try await bounded {
            while true {
                let status = try await MapHTTPClient.fetch(server.url("/started"), resource: .catalog)
                if String(data: status.data, encoding: .utf8) == "true" { return }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await bounded { try await pending.value } }
        #expect(terminalCount.withLock { $0 } == 1)
        do {
            _ = try await bounded { try await MapHTTPClient.fetch(server.url("/slow"), resource: .tile, timeout: 0.2) }
            Issue.record("Slow HTTP resource did not time out")
        } catch let error as URLError { #expect(error.code == .timedOut) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MapHTTPClient.fetch(server.url("/empty"), resource: .tile)
        }
        await #expect(throws: CancellationError.self) { try await bounded { try await cancelled.value } }
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

    private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask { try await Task.sleep(for: .seconds(5)); throw WaitError.timeout }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
    private enum WaitError: Error { case timeout }

    /// Sole test owner of a localhost subprocess. Startup and teardown are bounded;
    /// handlers use daemon threads so disconnected clients cannot retain the child.
    private final class Server: @unchecked Sendable {
        private let process: Process
        private let base: URL
        private let stopped = Mutex(false)
        init() throws {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-u", "-c", Self.script]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            self.process = process
            let output = Mutex<Data?>(nil), ready = DispatchSemaphore(value: 0)
            let handle = pipe.fileHandleForReading
            DispatchQueue.global().async {
                var bytes = Data()
                while bytes.count < 256 {
                    guard let byte = try? handle.read(upToCount: 1), !byte.isEmpty else { break }
                    bytes.append(byte)
                    if byte.last == 10 { break }
                }
                output.withLock { $0 = bytes }
                ready.signal()
            }
            guard ready.wait(timeout: .now() + 5) == .success,
                  let data = output.withLock({ $0 }),
                  let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: text), url.host == "127.0.0.1" else {
                Self.terminate(process); throw WaitError.timeout
            }
            self.base = url
        }
        func url(_ path: String) -> URL { URL(string: path, relativeTo: base)!.absoluteURL }
        func stop() {
            let shouldStop = stopped.withLock { value in if value { return false }; value = true; return true }
            if shouldStop { Self.terminate(process) }
        }
        deinit { stop() }
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
import gzip, http.server, threading, time
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
class Server(http.server.ThreadingHTTPServer): daemon_threads = True
server = Server(('127.0.0.1',0), Handler)
print('http://127.0.0.1:%s/' % server.server_port, flush=True)
server.serve_forever()
"""#
    }
}
