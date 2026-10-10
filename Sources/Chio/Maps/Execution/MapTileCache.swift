import ChioFileSystem
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Explicit raw-tile persistence in an application-selected private directory.
/// One cooperative owner retains the directory and lock descriptors until close.
/// Tile limits count encoded bytes, including a replacement's temporary file;
/// the bounded manifest and empty lock file are additional overhead. Rename is
/// atomic for process interruption; this cache does not promise power-loss durability.
public actor MapTileCache {
    public nonisolated let source: OpenMapTilesSource

    public enum CacheError {
        case invalidConfiguration, alreadyInUse, sourceMismatch, unsupportedFormat
        case invalidDirectory, closed, ioFailure(Int32), corruptManifest
    }

    struct Entry {
        let data: Data
        let storedAt: TimeInterval
        let expiresAt: TimeInterval
    }

    private struct Record {
        let bytes: Int
        let storedAt: TimeInterval
    }

    private final class Ownership: @unchecked Sendable {
        let directory: Int32
        let lock: Int32
        init(directory: Int32, lock: Int32) { self.directory = directory; self.lock = lock }
        deinit { _ = MapTileCache.closeDescriptor(lock); _ = MapTileCache.closeDescriptor(directory) }
    }

    private enum Lifecycle {
        case open(Ownership), failed(Ownership), closed
    }

    private struct File {
        let name: String
        let bytes: Int
        let tile: MapTileCoordinate?
        let isTemporary: Bool
    }

    private static let hardMaximumBytes = 256 * 1_024 * 1_024
    private static let hardMaximumEntries = 1_024
    private static let manifestName = "manifest.json"
    private static let manifestTemporaryName = ".manifest.tmp"
    private static let lockName = ".lock"
    private let maximumBytes: Int
    private let maximumEntries: Int
    private let onWriteChunk: @Sendable (Int) -> Void
    private var lifecycle: Lifecycle
    private var ownership: Ownership? {
        switch lifecycle {
        case .open(let owner): return owner
        case .failed, .closed: return nil
        }
    }
    private var records: [MapTileCoordinate: Record]
    private var bytes: Int

    private init(source: OpenMapTilesSource, maximumBytes: Int, maximumEntries: Int,
                 ownership: Ownership, records: [MapTileCoordinate: Record],
                 onWriteChunk: @escaping @Sendable (Int) -> Void) {
        self.source = source; self.maximumBytes = maximumBytes; self.maximumEntries = maximumEntries
        self.onWriteChunk = onWriteChunk
        self.lifecycle = .open(ownership); self.records = records
        self.bytes = records.values.reduce(0) { $0 + $1.bytes }
    }

    public static func open(directory: URL, source: OpenMapTilesSource,
                            maximumBytes: Int = 128 * 1_024 * 1_024,
                            maximumEntries: Int = 256) throws -> MapTileCache {
        try open(directory: directory, source: source, maximumBytes: maximumBytes,
                 maximumEntries: maximumEntries, at: Date().timeIntervalSince1970)
    }

    /// The application clock is explicit in deterministic storage tests.
    static func open(directory: URL, source: OpenMapTilesSource,
                     maximumBytes: Int = 128 * 1_024 * 1_024,
                     maximumEntries: Int = 256, at now: TimeInterval,
                     onWriteChunk: @escaping @Sendable (Int) -> Void = { _ in }) throws -> MapTileCache {
        try Task.checkCancellation()
        let hasValidByteLimit = (1...hardMaximumBytes).contains(maximumBytes)
        let hasValidEntryLimit = (1...hardMaximumEntries).contains(maximumEntries)
        guard hasValidByteLimit, hasValidEntryLimit, now.isFinite else { throw CacheError.invalidConfiguration }
        guard directory.isFileURL else { throw CacheError.invalidDirectory }
        let manifest = try MapTileCacheFormat.manifest(for: source)
        let path = directory.standardizedFileURL.path
        guard !path.utf8.contains(0) else { throw CacheError.invalidDirectory }
        if mkdir(path, 0o700) != 0, errno != EEXIST { throw CacheError.ioFailure(errno) }
        let descriptor = openDirectory(path)
        guard descriptor >= 0 else { throw CacheError.invalidDirectory }
        var isDirectoryTransferred = false
        defer { if !isDirectoryTransferred { _ = closeDescriptor(descriptor) } }
        // Inspect a bounded directory before creating or removing any owned file.
        _ = try inspect(descriptor)
        let lock = openat(descriptor, lockName, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw CacheError.ioFailure(errno) }
        var isLockTransferred = false
        defer { if !isLockTransferred { _ = closeDescriptor(lock) } }
        if chio_cache_try_lock(lock) != 0 {
            let failure = errno
            if failure == EWOULDBLOCK || failure == EAGAIN { throw CacheError.alreadyInUse }
            throw CacheError.ioFailure(failure)
        }
        let files = try inspect(descriptor)
        let published = files.filter { $0.tile != nil && !$0.isTemporary }
        if files.contains(where: { $0.name == manifestName }) {
            let encoded = try readFile(manifestName, directory: descriptor, limit: MapTileCacheFormat.maximumManifestBytes)
            guard let encoded else { throw CacheError.corruptManifest }
            try MapTileCacheFormat.validateManifest(encoded, source: source)
        } else {
            guard published.isEmpty else { throw CacheError.corruptManifest }
            try removeFile(manifestTemporaryName, directory: descriptor)
            try writeFile(manifest, temporary: manifestTemporaryName, destination: manifestName, directory: descriptor)
        }
        // Unknown shapes and incompatible manifests have now rejected without cleanup.
        var records: [MapTileCoordinate: Record] = [:]
        for file in files {
            try Task.checkCancellation()
            if file.isTemporary { try removeFile(file.name, directory: descriptor); continue }
            guard let tile = file.tile else { continue }
            let encoded = try readFile(file.name, directory: descriptor,
                                       limit: MapTileCacheFormat.maximumPayloadBytes + MapTileCacheFormat.overheadBytes)
            let entry = try encoded.flatMap { try MapTileCacheFormat.decode($0, tile: tile) }
            if let entry, now >= entry.storedAt, now < entry.expiresAt {
                records[tile] = Record(bytes: file.bytes, storedAt: entry.storedAt)
            } else { try removeFile(file.name, directory: descriptor) }
        }
        var bytes = records.values.reduce(0) { $0 + $1.bytes }
        while records.count > maximumEntries || bytes > maximumBytes {
            guard let tile = oldest(in: records) else { break }
            try removeFile(name(for: tile), directory: descriptor)
            bytes -= records.removeValue(forKey: tile)!.bytes
        }
        try Task.checkCancellation()
        let ownership = Ownership(directory: descriptor, lock: lock)
        isDirectoryTransferred = true; isLockTransferred = true
        return MapTileCache(source: source, maximumBytes: maximumBytes, maximumEntries: maximumEntries,
                            ownership: ownership, records: records, onWriteChunk: onWriteChunk)
    }

    /// Releases the cooperative lock. Repeated closes are harmless.
    public func close() { lifecycle = .closed; records = [:]; bytes = 0 }

    func ensureOpen() throws { guard ownership != nil else { throw CacheError.closed } }

    func read(_ tile: MapTileCoordinate, at now: TimeInterval) throws -> Entry? {
        try ensureOpen()
        try Task.checkCancellation()
        guard now.isFinite else { throw CacheError.invalidConfiguration }
        guard records[tile] != nil, let ownership else { return nil }
        let encoded = try Self.readFile(Self.name(for: tile), directory: ownership.directory,
            limit: MapTileCacheFormat.maximumPayloadBytes + MapTileCacheFormat.overheadBytes)
        let entry = try encoded.flatMap { try MapTileCacheFormat.decode($0, tile: tile) }
        guard let entry, now >= entry.storedAt, now < entry.expiresAt else { try remove(tile); return nil }
        try Task.checkCancellation()
        return entry
    }

    func store(_ data: Data, for tile: MapTileCoordinate,
               storedAt: TimeInterval, expiresAt: TimeInterval) throws {
        try ensureOpen()
        try Task.checkCancellation()
        guard source.zoomRange.contains(tile.zoom) else { throw CacheError.invalidConfiguration }
        let entry = Entry(data: data, storedAt: storedAt, expiresAt: expiresAt)
        let encoded = try MapTileCacheFormat.encode(entry, tile: tile)
        guard let ownership else { throw CacheError.closed }
        if encoded.count > maximumBytes { try remove(tile); return }
        // The existing replacement and its new sibling both occupy disk until rename.
        // Pre-evict before staging, including the replaced tile when necessary.
        while bytes + encoded.count > maximumBytes || records.count - (records[tile] == nil ? 0 : 1) >= maximumEntries {
            guard let oldest = Self.oldest(in: records) else { break }
            try remove(oldest)
        }
        let destination = Self.name(for: tile)
        do {
            try Self.writeFile(encoded, temporary: destination + ".tmp", destination: destination,
                               directory: ownership.directory, onWriteChunk: onWriteChunk)
        } catch is CancellationError {
            // writeFile propagates cancellation only after confirmed sibling cleanup;
            // any completed pre-evictions already updated this accounting snapshot.
            throw CancellationError()
        } catch {
            // Failed cleanup may leave a staged sibling. Retain the lock but stop
            // using this accounting snapshot until explicit close and reopen.
            lifecycle = .failed(ownership)
            throw error
        }
        if let prior = records[tile] { bytes -= prior.bytes }
        records[tile] = Record(bytes: encoded.count, storedAt: storedAt)
        bytes += encoded.count
    }

    func remove(_ tile: MapTileCoordinate) throws {
        try ensureOpen()
        try Task.checkCancellation()
        guard let ownership else { throw CacheError.closed }
        try Self.removeFile(Self.name(for: tile), directory: ownership.directory)
        if let removed = records.removeValue(forKey: tile) { bytes -= removed.bytes }
    }

    private static func oldest(in records: [MapTileCoordinate: Record]) -> MapTileCoordinate? {
        records.min { left, right in
            if left.value.storedAt != right.value.storedAt { return left.value.storedAt < right.value.storedAt }
            let a = left.key, b = right.key
            if a.zoom != b.zoom { return a.zoom < b.zoom }
            if a.x != b.x { return a.x < b.x }
            return a.y < b.y
        }?.key
    }

    private static func name(for tile: MapTileCoordinate) -> String { "tile-\(tile.zoom)-\(tile.x)-\(tile.y).bin" }

    private static func inspect(_ directory: Int32) throws -> [File] {
        guard let stream = chio_cache_directory_stream(directory) else { throw CacheError.ioFailure(errno) }
        defer { _ = chio_cache_close_stream(stream) }
        var files: [File] = []
        var totalBytes = 0, publishedCount = 0, tileTemporaryCount = 0
        var nameBuffer = [CChar](repeating: 0, count: 256)
        while true {
            try Task.checkCancellation()
            let status = chio_cache_next_name(stream, &nameBuffer, nameBuffer.count)
            if status == 0 { break }
            guard status > 0 else { throw CacheError.ioFailure(errno) }
            let nameBytes = nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let name = String(decoding: nameBytes, as: UTF8.self)
            if name == "." || name == ".." { continue }
            guard files.count < hardMaximumEntries + 4 else { throw CacheError.invalidDirectory }
            var metadata = stat()
            guard fstatat(directory, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw CacheError.ioFailure(errno) }
            let isRegularFile = metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            guard isRegularFile, metadata.st_nlink == 1, metadata.st_size >= 0 else { throw CacheError.invalidDirectory }
            let bytes = Int(metadata.st_size)
            if name == lockName {
                guard bytes == 0 else { throw CacheError.invalidDirectory }
                files.append(File(name: name, bytes: bytes, tile: nil, isTemporary: false)); continue
            }
            if name == manifestName || name == manifestTemporaryName {
                guard bytes <= MapTileCacheFormat.maximumManifestBytes else { throw CacheError.invalidDirectory }
                files.append(File(name: name, bytes: bytes, tile: nil, isTemporary: name == manifestTemporaryName)); continue
            }
            let isTemporary = name.hasSuffix(".tmp")
            let baseName = isTemporary ? String(name.dropLast(4)) : name
            guard baseName.hasPrefix("tile-"), baseName.hasSuffix(".bin") else { throw CacheError.invalidDirectory }
            let parts = baseName.dropFirst(5).dropLast(4).split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, let zoom = Int(parts[0]), let x = Int(parts[1]), let y = Int(parts[2]),
                  let tile = try? MapTileCoordinate(zoom: zoom, x: x, y: y), Self.name(for: tile) == baseName
            else { throw CacheError.invalidDirectory }
            guard bytes <= MapTileCacheFormat.maximumPayloadBytes + MapTileCacheFormat.overheadBytes else {
                throw CacheError.invalidDirectory
            }
            if isTemporary { tileTemporaryCount += 1 } else { publishedCount += 1 }
            totalBytes += bytes
            let hasBoundedPublishedCount = publishedCount <= hardMaximumEntries
            let hasSingleTileTemporary = tileTemporaryCount <= 1
            let hasBoundedBytes = totalBytes <= hardMaximumBytes
            guard hasBoundedPublishedCount, hasSingleTileTemporary, hasBoundedBytes else { throw CacheError.invalidDirectory }
            files.append(File(name: name, bytes: bytes, tile: tile, isTemporary: isTemporary))
        }
        return files
    }

    private static func readFile(_ name: String, directory: Int32, limit: Int) throws -> Data? {
        try Task.checkCancellation()
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw CacheError.ioFailure(errno)
        }
        defer { _ = closeDescriptor(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw CacheError.ioFailure(errno) }
        let isRegularFile = metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
        guard isRegularFile, metadata.st_nlink == 1 else { throw CacheError.invalidDirectory }
        guard metadata.st_size >= 0, metadata.st_size <= limit else { return nil }
        var data = Data(count: Int(metadata.st_size))
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                let count = readDescriptor(descriptor, buffer.baseAddress!.advanced(by: offset), min(65_536, buffer.count - offset))
                if count < 0 { if errno == EINTR { continue }; throw CacheError.ioFailure(errno) }
                if count == 0 { throw CacheError.ioFailure(EIO) }
                offset += count
            }
        }
        return data
    }

    private static func writeFile(_ data: Data, temporary: String, destination: String, directory: Int32,
                                  onWriteChunk: @Sendable (Int) -> Void = { _ in }) throws {
        try Task.checkCancellation()
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CacheError.ioFailure(errno) }
        var needsClose = true
        defer { if needsClose { _ = closeDescriptor(descriptor) } }
        do {
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    try Task.checkCancellation()
                    let count = writeDescriptor(descriptor, buffer.baseAddress!.advanced(by: offset), min(65_536, buffer.count - offset))
                    if count < 0 { if errno == EINTR { continue }; throw CacheError.ioFailure(errno) }
                    guard count > 0 else { throw CacheError.ioFailure(EIO) }
                    offset += count
                    onWriteChunk(offset)
                }
            }
            needsClose = false
            guard closeDescriptor(descriptor) == 0 else { throw CacheError.ioFailure(errno) }
            try Task.checkCancellation()
            guard renameat(directory, temporary, directory, destination) == 0 else { throw CacheError.ioFailure(errno) }
        } catch {
            let original = error
            // Cleanup failure is observable; no subsequent store may proceed with
            // accounting that omits this remaining temporary file.
            try removeFile(temporary, directory: directory)
            throw original
        }
    }

    private static func openDirectory(_ path: String) -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        #if canImport(Darwin)
        return Darwin.open(path, flags)
        #else
        return Glibc.open(path, flags)
        #endif
    }

    private static func closeDescriptor(_ descriptor: Int32) -> Int32 {
        #if canImport(Darwin)
        return Darwin.close(descriptor)
        #else
        return Glibc.close(descriptor)
        #endif
    }

    private static func readDescriptor(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.read(descriptor, buffer, count)
        #else
        return Glibc.read(descriptor, buffer, count)
        #endif
    }

    private static func writeDescriptor(_ descriptor: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.write(descriptor, buffer, count)
        #else
        return Glibc.write(descriptor, buffer, count)
        #endif
    }

    private static func removeFile(_ name: String, directory: Int32) throws {
        if unlinkat(directory, name, 0) != 0, errno != ENOENT { throw CacheError.ioFailure(errno) }
    }
}

extension MapTileCache.CacheError: Error {}
extension MapTileCache.CacheError: Equatable {}
extension MapTileCache.CacheError: Sendable {}
extension MapTileCache.Entry: Sendable {}
