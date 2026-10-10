@testable import Chio
import Foundation
import Testing

struct MapTilePackTests {
    private enum FixtureError: Error { case callback }


    @Test("Complete raw tiles reopen on read-only storage with independent readers and close")
    func readOnlyRoundTrip() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("pack.bin")
        let plan = try plan()
        let metadata = try metadata()
        let pack = try await MapTilePack.create(at: location, plan: plan, metadata: metadata) { _ in Data() }
        #expect(pack.plan == plan && pack.metadata == metadata)
        #expect(try await pack.read(plan.tiles[0]) == Data())
        let outside = try MapTileCoordinate(zoom: 1, x: 0, y: 0)
        #expect(try await pack.read(outside) == nil)
        let bytes = try Data(contentsOf: location)
        let before = try FileManager.default.attributesOfItem(atPath: location.path)[.modificationDate] as? Date
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        let first = try MapTilePack.open(at: location)
        let second = try MapTilePack.open(at: location)
        #expect(try await first.read(plan.tiles[0]) == Data())
        await first.close()
        await first.close()
        await #expect(throws: MapTilePack.PackError.closed) { try await first.ensureOpen() }
        await #expect(throws: MapTilePack.PackError.closed) { try await first.read(outside) }
        #expect(try await second.read(plan.tiles[0]) == Data())
        #expect(try Data(contentsOf: location) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["pack.bin"])
        let after = try FileManager.default.attributesOfItem(atPath: location.path)[.modificationDate] as? Date
        #expect(before == after)
        await second.close()
        await pack.close()
    }

    @Test("Byte budgets and callback failure leave no complete destination or temporary")
    func failedPreparation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("pack.bin")
        let smallPlan = try plan(range: 1...2, maximumBytes: 1)
        await #expect(throws: MapTilePack.PackError.invalidConfiguration) {
            try await MapTilePack.create(at: location, plan: smallPlan, metadata: metadata()) { _ in Data([1]) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        await #expect(throws: FixtureError.self) {
            try await MapTilePack.create(at: location, plan: smallPlan, metadata: metadata()) { tile in
                #expect(!FileManager.default.fileExists(atPath: location.path))
                if tile.zoom == 2 { throw FixtureError.callback }
                return Data()
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        let largerPlan = try plan(maximumBytes: 32 * 1_024 * 1_024)
        await #expect(throws: MapTilePack.PackError.invalidConfiguration) {
            try await MapTilePack.create(at: location, plan: largerPlan, metadata: metadata()) { _ in
                Data(repeating: 1, count: 16 * 1_024 * 1_024 + 1)
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Cancellation after a supplied callback removes only its exclusively owned sibling")
    func cancellation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unrelated = directory.appendingPathComponent(".chio-pack-unrelated.tmp")
        try Data([9]).write(to: unrelated)
        let location = directory.appendingPathComponent("pack.bin")
        let plan = try plan()
        let metadata = try metadata()
        let task = Task {
            try await MapTilePack.create(at: location, plan: plan, metadata: metadata) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return Data([1])
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [unrelated.lastPathComponent])
        #expect(try Data(contentsOf: unrelated) == Data([9]))
    }

    @Test("Publication preserves existing files, including a destination appearing during callbacks")
    func noOverwrite() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("pack.bin")
        let sentinel = Data([9, 8, 7])
        try sentinel.write(to: location)
        await #expect(throws: MapTilePack.PackError.destinationExists) {
            try await MapTilePack.create(at: location, plan: plan(), metadata: metadata()) { _ in
                Issue.record("Existing destinations must reject before tile callbacks")
                return Data()
            }
        }
        #expect(try Data(contentsOf: location) == sentinel)
        try FileManager.default.removeItem(at: location)
        await #expect(throws: MapTilePack.PackError.destinationExists) {
            try await MapTilePack.create(at: location, plan: plan(), metadata: metadata()) { _ in
                try sentinel.write(to: location)
                return Data([1])
            }
        }
        #expect(try Data(contentsOf: location) == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["pack.bin"])
    }

    @Test("Retained descriptors preserve pack identity across path replacement and matching metadata")
    func retainedIdentity() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("pack.bin")
        let plan = try plan()
        let metadata = try metadata()
        let first = try await MapTilePack.create(at: location, plan: plan, metadata: metadata) { _ in Data([1]) }
        try FileManager.default.moveItem(at: location, to: directory.appendingPathComponent("prior.bin"))
        let second = try await MapTilePack.create(at: location, plan: plan, metadata: metadata) { _ in Data([2]) }
        #expect(first.metadata == second.metadata && first.plan == second.plan)
        #expect(try await first.read(plan.tiles[0]) == Data([1]))
        #expect(try await second.read(plan.tiles[0]) == Data([2]))
        await first.close()
        await second.close()
    }

    @Test("Truncated, extra, unsupported and index-corrupt files reject without repair")
    func malformedFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("pack.bin")
        let pack = try await MapTilePack.create(at: location, plan: plan(), metadata: metadata()) { _ in Data([1]) }
        await pack.close()
        let original = try Data(contentsOf: location)
        var version = original
        version[8] = 2
        var indexCorrupt = original
        indexCorrupt[indexCorrupt.count - 8] ^= 1
        let inputs = [Data(), Data(original.prefix(39)), Data(original.dropLast()), original + Data([1]), indexCorrupt]
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        for input in inputs {
            try input.write(to: location)
            #expect(throws: MapTilePack.PackError.corruptPack) { try MapTilePack.open(at: location) }
            #expect(try Data(contentsOf: location) == input)
        }
        try version.write(to: location)
        #expect(throws: MapTilePack.PackError.unsupportedFormat) { try MapTilePack.open(at: location) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["pack.bin"])
    }

    @Test("Payload corruption and post-open truncation fail advertised reads")
    func corruptPayload() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("pack.bin")
        let plan = try plan()
        let pack = try await MapTilePack.create(at: location, plan: plan, metadata: metadata()) { _ in Data([1]) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        let writer = try FileHandle(forWritingTo: location)
        defer { try? writer.close() }
        try writer.seek(toOffset: UInt64(MapTilePackFormat.headerBytes))
        try writer.write(contentsOf: Data([2]))
        await #expect(throws: MapTilePack.PackError.corruptPack) { try await pack.read(plan.tiles[0]) }
        let reopened = try MapTilePack.open(at: location)
        await #expect(throws: MapTilePack.PackError.corruptPack) { try await reopened.read(plan.tiles[0]) }
        try writer.truncate(atOffset: 0)
        await #expect(throws: MapTilePack.PackError.corruptPack) { try await pack.read(plan.tiles[0]) }
        await pack.close()
        await reopened.close()
    }

    private func plan(range: ClosedRange<Int> = 2...2, maximumBytes: Int = 100) throws -> MapTilePackPlan {
        let bounds = try MapCoverage.Bounds(southwest: MapCoordinate(latitude: 1, longitude: 1),
                                           northeast: MapCoordinate(latitude: 2, longitude: 2))
        return try MapTilePackPlan(bounds: bounds, zoomRange: range, maximumBytes: maximumBytes)
    }

    private func metadata() throws -> MapSourceMetadata {
        let url = try #require(URL(string: "https://example.test/source"))
        return try MapSourceMetadata(attribution: "Credit", license: "License", licenseURL: url,
                                     sourceURL: url, sourceRevision: "revision")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chio-pack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
