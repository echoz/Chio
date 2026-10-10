import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// An explicitly opened, immutable raw-tile backing store. Each reader retains
/// its own read-only descriptor; a loader must keep one reader for its lifetime.
/// Use an application-controlled directory and do not mutate published files.
/// Atomic publication protects process interruption, not power-loss durability.
public actor MapTilePack {
    public nonisolated let plan: MapTilePackPlan
    public nonisolated let metadata: MapSourceMetadata

    public enum PackError {
        case invalidConfiguration, invalidLocation, destinationExists, unsupportedFormat
        case corruptPack, closed, ioFailure(Int32)
    }

    private final class Ownership: @unchecked Sendable {
        let descriptor: Int32
        init(descriptor: Int32) { self.descriptor = descriptor }
        deinit { _ = MapTilePack.closeDescriptor(descriptor) }
    }

    private let entries: [MapTileCoordinate: MapTilePackFormat.Entry]
    private let fileBytes: Int
    private var ownership: Ownership?

    private init(plan: MapTilePackPlan, metadata: MapSourceMetadata,
                 entries: [MapTilePackFormat.Entry], fileBytes: Int, ownership: Ownership) {
        self.plan = plan
        self.metadata = metadata
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.tile, $0) })
        self.fileBytes = fileBytes
        self.ownership = ownership
    }

    /// Acquires every advertised address from application-supplied bytes, then
    /// publishes one complete file without replacing an existing destination.
    /// No provider discovery, transport, cache expiry or eviction is involved.
    /// If sibling cleanup fails after publication, an I/O error can leave the
    /// complete destination present. The caller can explicitly open that file.
    public static func create(at location: URL, plan: MapTilePackPlan, metadata: MapSourceMetadata,
                              tileData: @escaping @Sendable (MapTileCoordinate) async throws -> Data) async throws -> MapTilePack {
        try Task.checkCancellation()
        try validateLocation(location)
        let manifest = try MapTilePackFormat.manifest(plan: plan, metadata: metadata)
        let parent = location.deletingLastPathComponent().standardizedFileURL.path
        let directory = openDescriptor(parent, flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directory >= 0 else { throw PackError.ioFailure(errno) }
        defer { _ = closeDescriptor(directory) }
        let destination = location.lastPathComponent
        var existing = stat()
        if fstatat(directory, destination, &existing, AT_SYMLINK_NOFOLLOW) == 0 { throw PackError.destinationExists }
        guard errno == ENOENT else { throw PackError.ioFailure(errno) }
        let temporary = ".chio-pack-\(UUID().uuidString).tmp"
        let writer = openat(directory, temporary, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard writer >= 0 else { throw PackError.ioFailure(errno) }
        defer { _ = closeDescriptor(writer) }
        do {
            // The uncommitted header stays invalid until every callback succeeds.
            try write(Data(repeating: 0, count: MapTilePackFormat.headerBytes), descriptor: writer, offset: 0)
            var entries: [MapTilePackFormat.Entry] = []
            var rawBytes = 0
            for tile in plan.tiles {
                try Task.checkCancellation()
                let payload = try await tileData(tile)
                try Task.checkCancellation()
                let hasBoundedTile = payload.count <= MapTilePackFormat.maximumPayloadBytes
                let fitsRemainingBudget = payload.count <= plan.maximumBytes - rawBytes
                guard hasBoundedTile, fitsRemainingBudget else { throw PackError.invalidConfiguration }
                let checksum = try MapTileChecksum.crc32(payload)
                try write(payload, descriptor: writer, offset: MapTilePackFormat.headerBytes + rawBytes)
                entries.append(MapTilePackFormat.Entry(tile: tile, offset: rawBytes,
                                                       length: payload.count, checksum: checksum))
                rawBytes += payload.count
            }
            let index = MapTilePackFormat.index(entries)
            let header = try MapTilePackFormat.header(manifest: manifest, index: index,
                                                      count: entries.count, rawBytes: rawBytes)
            let manifestOffset = MapTilePackFormat.headerBytes + rawBytes
            try write(manifest, descriptor: writer, offset: manifestOffset)
            try write(index, descriptor: writer, offset: manifestOffset + manifest.count)
            try write(header, descriptor: writer, offset: 0)
            guard fchmod(writer, 0o444) == 0 else { throw PackError.ioFailure(errno) }
            // Validate and retain a separate read-only descriptor before committing.
            let readerDescriptor = openat(directory, temporary, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard readerDescriptor >= 0 else { throw PackError.ioFailure(errno) }
            let owner = Ownership(descriptor: readerDescriptor)
            let reader = try opened(owner)
            try Task.checkCancellation()
            // linkat fails if anything occupies the destination, including a symlink.
            guard linkat(directory, temporary, directory, destination, 0) == 0 else {
                if errno == EEXIST { throw PackError.destinationExists }
                throw PackError.ioFailure(errno)
            }
            guard unlinkat(directory, temporary, 0) == 0 else { throw PackError.ioFailure(errno) }
            return reader
        } catch {
            // Only this exclusively created sibling is eligible for cleanup.
            if unlinkat(directory, temporary, 0) != 0, errno != ENOENT { throw PackError.ioFailure(errno) }
            throw error
        }
    }

    /// Opens without creating lockfiles, repair files or application access metadata.
    public static func open(at location: URL) throws -> MapTilePack {
        try Task.checkCancellation()
        try validateLocation(location)
        // A supplied FIFO must not block before regular-file validation.
        let descriptor = openDescriptor(location.standardizedFileURL.path,
                                        flags: O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw PackError.ioFailure(errno) }
        return try opened(Ownership(descriptor: descriptor))
    }

    public func close() { ownership = nil }

    func ensureOpen() throws { guard ownership != nil else { throw PackError.closed } }

    /// Nil means outside the advertised plan. An advertised but unreadable tile
    /// rejects, including empty-file truncation; zero-length valid tiles succeed.
    func read(_ tile: MapTileCoordinate) throws -> Data? {
        try ensureOpen()
        try Task.checkCancellation()
        guard let entry = entries[tile] else { return nil }
        guard let ownership else { throw PackError.closed }
        let actualBytes = try Self.regularFileBytes(ownership.descriptor)
        guard actualBytes == fileBytes else { throw PackError.corruptPack }
        let payload = try Self.read(descriptor: ownership.descriptor,
                                    offset: MapTilePackFormat.headerBytes + entry.offset, length: entry.length)
        guard try MapTileChecksum.crc32(payload) == entry.checksum else { throw PackError.corruptPack }
        return payload
    }

    private static func opened(_ ownership: Ownership) throws -> MapTilePack {
        let fileBytes = try regularFileBytes(ownership.descriptor)
        let header = try read(descriptor: ownership.descriptor, offset: 0, length: MapTilePackFormat.headerBytes)
        let framing = try MapTilePackFormat.decodeHeader(header)
        guard fileBytes == framing.fileBytes else { throw PackError.corruptPack }
        let manifestOffset = MapTilePackFormat.headerBytes + framing.rawBytes
        let manifest = try read(descriptor: ownership.descriptor, offset: manifestOffset, length: framing.manifestBytes)
        let index = try read(descriptor: ownership.descriptor, offset: manifestOffset + manifest.count, length: framing.indexBytes)
        let (decoded, entries) = try MapTilePackFormat.decode(header: header, manifest: manifest, index: index)
        return MapTilePack(plan: decoded.plan, metadata: decoded.metadata, entries: entries,
                           fileBytes: fileBytes, ownership: ownership)
    }

    private static func validateLocation(_ location: URL) throws {
        let hasLocalFileURL = location.isFileURL && (location.host == nil || location.host == "localhost" || location.host == "")
        let hasNoNul = !location.path.utf8.contains(0)
        guard hasLocalFileURL, hasNoNul else { throw PackError.invalidLocation }
        let name = location.lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != ".." else { throw PackError.invalidLocation }
    }

    private static func regularFileBytes(_ descriptor: Int32) throws -> Int {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw PackError.ioFailure(errno) }
        let isRegular = status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
        let hasBoundedLength = status.st_size >= 0 && status.st_size <= MapTilePackPlan.hardMaximumBytes
            + MapTilePackFormat.headerBytes + MapTilePackFormat.maximumManifestBytes
            + MapTilePackPlan.maximumTiles * MapTilePackFormat.entryBytes
        guard isRegular, hasBoundedLength else { throw PackError.corruptPack }
        return Int(status.st_size)
    }

    private static func read(descriptor: Int32, offset: Int, length: Int) throws -> Data {
        var data = Data(count: length)
        try data.withUnsafeMutableBytes { buffer in
            var completed = 0
            while completed < length {
                try Task.checkCancellation()
                let count = pread(descriptor, buffer.baseAddress!.advanced(by: completed),
                                  min(65_536, length - completed), off_t(offset + completed))
                if count < 0 {
                    if errno == EINTR { continue }
                    throw PackError.ioFailure(errno)
                }
                guard count > 0 else { throw PackError.corruptPack }
                completed += count
            }
        }
        return data
    }

    private static func write(_ data: Data, descriptor: Int32, offset: Int) throws {
        try data.withUnsafeBytes { buffer in
            var completed = 0
            while completed < data.count {
                try Task.checkCancellation()
                let count = pwrite(descriptor, buffer.baseAddress!.advanced(by: completed),
                                   min(65_536, data.count - completed), off_t(offset + completed))
                if count < 0 {
                    if errno == EINTR { continue }
                    throw PackError.ioFailure(errno)
                }
                guard count > 0 else { throw PackError.ioFailure(EIO) }
                completed += count
            }
        }
    }

    private static func openDescriptor(_ path: String, flags: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.open(path, flags)
        #else
        Glibc.open(path, flags)
        #endif
    }

    private static func closeDescriptor(_ descriptor: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.close(descriptor)
        #else
        Glibc.close(descriptor)
        #endif
    }
}

extension MapTilePack.PackError: Error {}
extension MapTilePack.PackError: Equatable {}
extension MapTilePack.PackError: Sendable {}
