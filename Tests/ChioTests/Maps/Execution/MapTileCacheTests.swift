@testable import Chio
import Foundation
import Testing

struct MapTileCacheTests {
    @Test("Raw bytes and freshness survive close/reopen; close invalidates ownership")
    func roundTripAndClose() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try source()
        let tile = try tile(0)
        let cache = try MapTileCache.open(directory: directory, source: source, at: 100)
        try await cache.store(Data([0, 128, 255]), for: tile, storedAt: 100, expiresAt: 160)
        let first = try await cache.read(tile, at: 110)
        #expect(first?.data == Data([0, 128, 255]))
        #expect(first?.storedAt == 100 && first?.expiresAt == 160)
        await cache.close()
        await cache.close()
        await #expect(throws: MapTileCache.CacheError.closed) { try await cache.read(tile, at: 110) }
        await #expect(throws: MapTileCache.CacheError.closed) {
            try await cache.store(Data(), for: tile, storedAt: 110, expiresAt: 120)
        }
        await #expect(throws: MapTileCache.CacheError.closed) { try await cache.remove(tile) }
        await #expect(throws: MapTileCache.CacheError.closed) { try await cache.ensureOpen() }
        let reopened = try MapTileCache.open(directory: directory, source: source, at: 110)
        #expect(try await reopened.read(tile, at: 110)?.data == first?.data)
        await reopened.close()
    }

    @Test("The retained inode excludes another owner until explicit close")
    func duplicateOwner() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try source()
        let cache = try MapTileCache.open(directory: directory, source: source, at: 0)
        #expect(throws: MapTileCache.CacheError.alreadyInUse) {
            try MapTileCache.open(directory: directory, source: source, at: 0)
        }
        await cache.close()
        let next = try MapTileCache.open(directory: directory, source: source, at: 0)
        await next.close()
        #expect(try Data(contentsOf: directory.appendingPathComponent(".lock")).isEmpty)
    }

    @Test("Every source field binds the directory; mismatch and incompatible manifests preserve files")
    func manifestIsolationAndRejection() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try source()
        let tile = try tile(0)
        let cache = try MapTileCache.open(directory: directory, source: source, at: 100)
        try await cache.store(Data([1]), for: tile, storedAt: 100, expiresAt: 200)
        await cache.close()
        let entryURL = directory.appendingPathComponent("tile-2-0-0.bin")
        let original = try Data(contentsOf: entryURL)
        let mismatches = try [self.source(revision: "other"), self.source(template: "https://other.test/{z}/{x}/{y}"),
                              self.source(range: 0...10), self.source(attribution: "Another credit")]
        for mismatch in mismatches {
            #expect(throws: MapTileCache.CacheError.sourceMismatch) {
                try MapTileCache.open(directory: directory, source: mismatch, at: 110)
            }
            #expect(try Data(contentsOf: entryURL) == original)
        }
        let manifestURL = directory.appendingPathComponent("manifest.json")
        try Data("{\"version\":2}".utf8).write(to: manifestURL)
        #expect(throws: MapTileCache.CacheError.unsupportedFormat) {
            try MapTileCache.open(directory: directory, source: source, at: 110)
        }
        #expect(try Data(contentsOf: entryURL) == original)
        try Data("{invalid".utf8).write(to: manifestURL)
        #expect(throws: MapTileCache.CacheError.corruptManifest) {
            try MapTileCache.open(directory: directory, source: source, at: 110)
        }
        #expect(try Data(contentsOf: entryURL) == original)
    }

    @Test("Entry count uses FIFO with stable address ties; reads do not refresh order")
    func entryLimitAndFIFO() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source(), maximumBytes: 300,
                                           maximumEntries: 2, at: 0)
        let tiles = try [tile(0), tile(1), tile(2)]
        for tile in tiles.prefix(2) { try await cache.store(Data([1]), for: tile, storedAt: 0, expiresAt: 100) }
        #expect(try await cache.read(tiles[0], at: 1) != nil)
        try await cache.store(Data([2]), for: tiles[2], storedAt: 1, expiresAt: 100)
        #expect(try await cache.read(tiles[0], at: 2) == nil)
        #expect(try await cache.read(tiles[1], at: 2) != nil)
        #expect(try await cache.read(tiles[2], at: 2) != nil)
        await cache.close()
    }

    @Test("Encoded-byte limits account for the previous entry plus replacement staging")
    func byteLimitAndReplacement() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source(), maximumBytes: 100, at: 0)
        let first = try tile(0), second = try tile(1)
        // Each two-byte payload occupies fifty bytes with framing and checksum.
        try await cache.store(Data([1, 1]), for: first, storedAt: 0, expiresAt: 100)
        try await cache.store(Data([2, 2]), for: second, storedAt: 1, expiresAt: 100)
        try await cache.store(Data([3, 3]), for: second, storedAt: 2, expiresAt: 100)
        #expect(try await cache.read(first, at: 3) == nil)
        #expect(try await cache.read(second, at: 3)?.data == Data([3, 3]))
        #expect(try tileBytes(in: directory) == 50)
        // A response larger than this configured cache is usable but not retained.
        try await cache.store(Data(repeating: 4, count: 101), for: second, storedAt: 3, expiresAt: 100)
        #expect(try await cache.read(second, at: 4) == nil)
        #expect(try tileBytes(in: directory) == 0)
        await cache.close()
    }

    @Test("Checksum protects bytes and freshness/address headers; truncation becomes a miss")
    func corruptEntries() async throws {
        for offset in [12, 24, 32, 40, 44, 48] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = try MapTileCache.open(directory: directory, source: source(), at: 100)
            let tile = try tile(0)
            try await cache.store(Data([7, 8, 9]), for: tile, storedAt: 100, expiresAt: 200)
            let url = directory.appendingPathComponent("tile-2-0-0.bin")
            var encoded = try Data(contentsOf: url)
            encoded[offset] ^= 1
            try encoded.write(to: url)
            #expect(try await cache.read(tile, at: 110) == nil)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            await cache.close()
        }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 100)
        let tile = try tile(0)
        try await cache.store(Data([7]), for: tile, storedAt: 100, expiresAt: 200)
        await cache.close()
        let url = directory.appendingPathComponent("tile-2-0-0.bin")
        try Data([1, 2]).write(to: url)
        let reopened = try MapTileCache.open(directory: directory, source: source(), at: 110)
        #expect(try await reopened.read(tile, at: 110) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        await reopened.close()
    }

    @Test("Expiry and backwards wall time delete stale entries at read and startup")
    func freshnessAndBackwardsClock() async throws {
        for now: TimeInterval in [99, 200] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let tile = try tile(0)
            let cache = try MapTileCache.open(directory: directory, source: source(), at: 100)
            try await cache.store(Data([1]), for: tile, storedAt: 100, expiresAt: 200)
            #expect(try await cache.read(tile, at: now) == nil)
            try await cache.store(Data([1]), for: tile, storedAt: 100, expiresAt: 200)
            await cache.close()
            let reopened = try MapTileCache.open(directory: directory, source: source(), at: now)
            #expect(try await reopened.read(tile, at: 150) == nil)
            await reopened.close()
        }
    }

    @Test("Unknown names, subdirectories and symlinks reject before temporary cleanup")
    func unexpectedDirectoryShapes() async throws {
        for shape in 0..<3 {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = try MapTileCache.open(directory: directory, source: source(), at: 0)
            await cache.close()
            let temporary = directory.appendingPathComponent("tile-2-0-0.bin.tmp")
            try Data([1]).write(to: temporary)
            let foreign = directory.appendingPathComponent(shape == 2 ? "tile-2-1-0.bin" : "foreign")
            if shape == 0 { try Data([2]).write(to: foreign) }
            if shape == 1 { try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false) }
            if shape == 2 { try FileManager.default.createSymbolicLink(at: foreign, withDestinationURL: temporary) }
            #expect(throws: MapTileCache.CacheError.invalidDirectory) {
                try MapTileCache.open(directory: directory, source: source(), at: 0)
            }
            #expect(try Data(contentsOf: temporary) == Data([1]))
            #expect(FileManager.default.fileExists(atPath: foreign.path))
        }
        let directory = temporaryDirectory(), link = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: link); try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        #expect(throws: MapTileCache.CacheError.invalidDirectory) {
            try MapTileCache.open(directory: link, source: source(), at: 0)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Known interrupted siblings recover at open; initial partial manifest can be retried")
    func interruptedWriteRecovery() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let manifestTemporary = directory.appendingPathComponent(".manifest.tmp")
        try Data("{partial".utf8).write(to: manifestTemporary)
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 0)
        #expect(!FileManager.default.fileExists(atPath: manifestTemporary.path))
        let tile = try tile(0)
        try await cache.store(Data([7]), for: tile, storedAt: 0, expiresAt: 100)
        await cache.close()
        let temporary = directory.appendingPathComponent("tile-2-0-0.bin.tmp")
        try Data([1, 2]).write(to: temporary)
        let reopened = try MapTileCache.open(directory: directory, source: source(), at: 1)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(try await reopened.read(tile, at: 1)?.data == Data([7]))
        await reopened.close()
    }

    @Test("Configuration and freshness bounds reject before publication")
    func invalidLimitsAndTimes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for bytes in [0, -1, 256 * 1_024 * 1_024 + 1] {
            #expect(throws: MapTileCache.CacheError.invalidConfiguration) {
                try MapTileCache.open(directory: directory, source: source(), maximumBytes: bytes, at: 0)
            }
        }
        for count in [0, -1, 1_025] {
            #expect(throws: MapTileCache.CacheError.invalidConfiguration) {
                try MapTileCache.open(directory: directory, source: source(), maximumEntries: count, at: 0)
            }
        }
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 0)
        let tile = try tile(0)
        for expiry: TimeInterval in [0, -1, 1_801, .infinity, .nan] {
            await #expect(throws: MapTileCache.CacheError.invalidConfiguration) {
                try await cache.store(Data(), for: tile, storedAt: 0, expiresAt: expiry)
            }
        }
        #expect(try tileBytes(in: directory) == 0)
        await cache.close()
    }

    @Test("Reopen enforces smaller limits after validating the complete directory")
    func startupEviction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try MapTileCache.open(directory: directory, source: source(), at: 100)
        for x in 0..<3 { try await original.store(Data([UInt8(x)]), for: tile(x), storedAt: 100 + Double(x), expiresAt: 200) }
        await original.close()
        let limited = try MapTileCache.open(directory: directory, source: source(), maximumBytes: 98,
                                             maximumEntries: 2, at: 110)
        #expect(try await limited.read(tile(0), at: 110) == nil)
        #expect(try await limited.read(tile(1), at: 110)?.data == Data([1]))
        #expect(try await limited.read(tile(2), at: 110)?.data == Data([2]))
        #expect(try tileBytes(in: directory) == 98)
        await limited.close()
    }

    @Test("More than the hard file bound rejects without deleting valid names")
    func excessiveDirectoryCount() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 0)
        await cache.close()
        for index in 0..<1_025 {
            let name = "tile-6-\(index % 64)-\(index / 64).bin"
            try Data().write(to: directory.appendingPathComponent(name))
        }
        #expect(throws: MapTileCache.CacheError.invalidDirectory) {
            try MapTileCache.open(directory: directory, source: source(), at: 0)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1_027)
    }

    @Test("Ordinary read I/O failures propagate without becoming corrupt misses")
    func readIOFailure() async throws {
        let directory = temporaryDirectory(), target = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: target) }
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 0)
        let tile = try tile(0)
        try await cache.store(Data([1]), for: tile, storedAt: 0, expiresAt: 100)
        let url = directory.appendingPathComponent("tile-2-0-0.bin")
        try FileManager.default.removeItem(at: url)
        try Data([2]).write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        do {
            _ = try await cache.read(tile, at: 1)
            Issue.record("Expected a no-follow open failure")
        } catch let error as MapTileCache.CacheError {
            guard case .ioFailure = error else { Issue.record("Expected ordinary I/O error: \(error)"); return }
        }
        #expect(try Data(contentsOf: target) == Data([2]))
        #expect(FileManager.default.fileExists(atPath: url.path))
        await cache.close()
    }

    @Test("A sparse directory beyond the hard byte bound is rejected before cleanup")
    func excessiveDirectoryBytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 0)
        await cache.close()
        for index in 0..<17 {
            let url = directory.appendingPathComponent("tile-6-\(index)-0.bin")
            try Data().write(to: url)
            let file = try FileHandle(forWritingTo: url)
            try file.truncate(atOffset: 16 * 1_024 * 1_024)
            try file.close()
        }
        #expect(throws: MapTileCache.CacheError.invalidDirectory) {
            try MapTileCache.open(directory: directory, source: source(), at: 0)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 19)
    }

    @Test("Cancellation rejects storage before staging bytes")
    func cancelledStore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 0)
        let tile = try tile(0)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await cache.store(Data([1]), for: tile, storedAt: 0, expiresAt: 100)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try await cache.read(tile, at: 1) == nil)
        #expect(try tileBytes(in: directory) == 0)
        await cache.close()
    }

    @Test("Oversized source URLs reject before the cache creates its directory")
    func oversizedManifestSource() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversizedURL = try #require(URL(string: "https://example.test/" + String(repeating: "x", count: 100_000)))
        let metadata = try MapSourceMetadata(attribution: "Fixture", license: "Fixture",
            licenseURL: oversizedURL, sourceURL: URL(string: "https://example.test")!, sourceRevision: "fixture")
        let oversizedSource = try OpenMapTilesSource(template: "https://example.test/{z}/{x}/{y}",
                                                      zoomRange: 0...14, metadata: metadata)
        #expect(throws: MapTileCache.CacheError.invalidConfiguration) {
            try MapTileCache.open(directory: directory, source: oversizedSource, at: 0)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Staging failure retains the lock and old complete entry until close and recovery")
    func stagingFailureLifecycle() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try source()
        let tile = try tile(0)
        let cache = try MapTileCache.open(directory: directory, source: source, at: 0)
        try await cache.store(Data([1]), for: tile, storedAt: 0, expiresAt: 100)
        let temporary = directory.appendingPathComponent("tile-2-0-0.bin.tmp")
        try Data([7]).write(to: temporary)
        do {
            try await cache.store(Data([2]), for: tile, storedAt: 1, expiresAt: 100)
            Issue.record("Expected staging to reject an occupied sibling")
        } catch let error as MapTileCache.CacheError {
            guard case .ioFailure(let code) = error else { Issue.record("Expected I/O failure: \(error)"); return }
            #expect(code > 0)
        }
        await #expect(throws: MapTileCache.CacheError.closed) { try await cache.read(tile, at: 2) }
        await #expect(throws: MapTileCache.CacheError.closed) {
            try await cache.store(Data([3]), for: tile, storedAt: 2, expiresAt: 100)
        }
        await #expect(throws: MapTileCache.CacheError.closed) { try await cache.remove(tile) }
        #expect(throws: MapTileCache.CacheError.alreadyInUse) {
            try MapTileCache.open(directory: directory, source: source, at: 2)
        }
        #expect(try Data(contentsOf: temporary) == Data([7]))
        await cache.close()
        let reopened = try MapTileCache.open(directory: directory, source: source, at: 2)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(try await reopened.read(tile, at: 2)?.data == Data([1]))
        await reopened.close()
    }

    @Test("Rename failure leaves foreign directories intact and invalidates the retained owner")
    func renameFailureLifecycle() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try source()
        let first = try tile(0), replacement = try tile(1)
        let cache = try MapTileCache.open(directory: directory, source: source, at: 0)
        try await cache.store(Data([1]), for: first, storedAt: 0, expiresAt: 100)
        let occupiedDestination = directory.appendingPathComponent("tile-2-1-0.bin")
        try FileManager.default.createDirectory(at: occupiedDestination, withIntermediateDirectories: false)
        let foreign = occupiedDestination.appendingPathComponent("foreign")
        try Data([9]).write(to: foreign)
        do {
            try await cache.store(Data([2]), for: replacement, storedAt: 1, expiresAt: 100)
            Issue.record("Expected rename to reject a directory destination")
        } catch let error as MapTileCache.CacheError {
            guard case .ioFailure(let code) = error else { Issue.record("Expected I/O failure: \(error)"); return }
            #expect(code > 0)
        }
        #expect(try Data(contentsOf: foreign) == Data([9]))
        #expect(!FileManager.default.fileExists(atPath: occupiedDestination.path + ".tmp"))
        await #expect(throws: MapTileCache.CacheError.closed) { try await cache.ensureOpen() }
        // Only the test removes the intentionally introduced foreign directory;
        // an invalid shape rejects before the duplicate-owner lock check.
        try FileManager.default.removeItem(at: occupiedDestination)
        #expect(throws: MapTileCache.CacheError.alreadyInUse) {
            try MapTileCache.open(directory: directory, source: source, at: 2)
        }
        await cache.close()
        let reopened = try MapTileCache.open(directory: directory, source: source, at: 2)
        #expect(try await reopened.read(first, at: 2)?.data == Data([1]))
        #expect(try await reopened.read(replacement, at: 2) == nil)
        await reopened.close()
    }

    @Test("Version-one encoded bytes match an independent struct/zlib fixture")
    func independentFramingFixture() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 100)
        try await cache.store(Data([0, 128, 255]), for: tile(0), storedAt: 100, expiresAt: 160)
        // Independently produced with Python struct.pack little-endian fields and
        // zlib.crc32; expected checksum is 0xe9858a45 over header plus payload.
        let expected = "4348494f54494c450100000002000000000000000000000000000000000059400000000000006440030000000080ff458a85e9"
        let encoded = try Data(contentsOf: directory.appendingPathComponent("tile-2-0-0.bin"))
        let actual = encoded.map { String(format: "%02x", $0) }.joined()
        #expect(actual == expected)
        await cache.close()
    }

    @Test("Cancellation after a written chunk cleans staging and leaves accounting usable")
    func cancelledStagingRemainsOpen() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try tile(0), second = try tile(1)
        let cache = try MapTileCache.open(directory: directory, source: source(), maximumBytes: 70_048, at: 0,
            onWriteChunk: { bytes in
                if bytes >= 65_536 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        try await cache.store(Data([1]), for: first, storedAt: 0, expiresAt: 100)
        let cancelled = Task {
            try await cache.store(Data(repeating: 2, count: 70_000), for: second, storedAt: 1, expiresAt: 100)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        // The old entry was pre-evicted to admit staging. Cancellation must preserve
        // that accurate empty accounting rather than disabling the cache.
        #expect(try await cache.read(first, at: 2) == nil)
        #expect(try await cache.read(second, at: 2) == nil)
        #expect(try tileBytes(in: directory) == 0)
        try await cache.ensureOpen()
        try await cache.store(Data([3]), for: second, storedAt: 2, expiresAt: 100)
        #expect(try await cache.read(second, at: 3)?.data == Data([3]))
        await cache.close()
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("chio-cache-" + UUID().uuidString)
    }

    private func tile(_ x: Int) throws -> MapTileCoordinate { try MapTileCoordinate(zoom: 2, x: x, y: 0) }

    private func source(revision: String = "fixture", template: String = "https://example.test/{z}/{x}/{y}",
                        range: ClosedRange<Int> = 0...14, attribution: String = "Fixture") throws -> OpenMapTilesSource {
        try OpenMapTilesSource(template: template, zoomRange: range,
            metadata: MapSourceMetadata(attribution: attribution, license: "Fixture",
                licenseURL: URL(string: "https://example.test/license")!, sourceURL: URL(string: "https://example.test")!,
                sourceRevision: revision))
    }

    private func tileBytes(in directory: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.lastPathComponent.hasPrefix("tile-") }
            .reduce(0) { total, url in total + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    }
}
