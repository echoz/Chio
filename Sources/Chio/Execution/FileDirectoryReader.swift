import Foundation

/// Owns synchronous filesystem work away from the main actor.
actor FileDirectoryReader {
    enum Failure {
        case invalidLocation
        case notDirectory
        case notRegularFile
        case missing
        case unreadable
        case io(underlying: NSError)
    }

    private let fileManager = FileManager()

    /// Lists one directory without applying the application's file filter.
    func readDirectory(at location: URL, showsHiddenFiles: Bool) throws -> [FileEntry] {
        try Task.checkCancellation()
        let directory = try Self.normalizedLocation(location)
        let target = directory.resolvingSymlinksInPath()
        let type = try fileType(at: target)
        if type == .typeSymbolicLink { try checkUnresolvedLink(at: target) }
        guard type == .typeDirectory else { throw Failure.notDirectory }
        guard fileManager.isReadableFile(atPath: target.path),
              fileManager.isExecutableFile(atPath: target.path) else {
            throw Failure.unreadable
        }
        try Task.checkCancellation()
        let names: [String]
        do {
            // Foundation's URL listing can canonicalize parent paths and reject a
            // directory link. Read names at the target, retaining lexical identity.
            names = try fileManager.contentsOfDirectory(atPath: target.path)
        } catch {
            throw failure(for: error)
        }

        var entries: [FileEntry] = []
        for name in names {
            try Task.checkCancellation()
            let childPath = (directory.path == "/" ? "/" : directory.path + "/") + name
            let url = URL(fileURLWithPath: childPath, isDirectory: false)
            if !showsHiddenFiles {
                if url.lastPathComponent.hasPrefix(".") { continue }
                let isHidden = try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden
                if isHidden == true { continue }
            }
            try Task.checkCancellation()
            entries.append(try entry(at: url))
        }

        let sorted = entries.sorted { left, right in
            if (left.kind == .directory) != (right.kind == .directory) {
                return left.kind == .directory
            }
            let leftName = left.name.lowercased()
            let rightName = right.name.lowercased()
            if leftName != rightName { return leftName < rightName }
            if left.name != right.name { return left.name < right.name }
            return left.url.absoluteString < right.url.absoluteString
        }
        try Task.checkCancellation()
        return sorted
    }

    /// Rechecks the current regular-file kind and readability without reading contents.
    /// Returning a URL does not reserve the file or prevent later filesystem changes.
    func validateFile(at location: URL) throws -> URL {
        try Task.checkCancellation()
        let url = try Self.normalizedLocation(location)
        let target = url.resolvingSymlinksInPath()
        let type = try fileType(at: target)
        if type == .typeSymbolicLink { try checkUnresolvedLink(at: target) }
        guard type == .typeRegular else { throw Failure.notRegularFile }
        guard fileManager.isReadableFile(atPath: target.path) else { throw Failure.unreadable }
        try Task.checkCancellation()
        return url
    }

    private func checkUnresolvedLink(at url: URL) throws {
        try Task.checkCancellation()
        // resolvingSymlinksInPath may leave a dangling link unchanged. Existence
        // follows its target; reachability supplies diagnostics when available.
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            _ = try url.checkResourceIsReachable()
        } catch {
            throw failure(for: error)
        }
        // Some Foundation implementations consider the link itself reachable.
        // That observation does not make its absent target eligible.
        throw Failure.missing
    }

    private func entry(at url: URL) throws -> FileEntry {
        let originalType: FileAttributeType
        do {
            originalType = try fileType(at: url)
        } catch {
            return FileEntry(url: url, kind: .unavailable, isSymbolicLink: false)
        }
        let isSymbolicLink = originalType == .typeSymbolicLink
        try Task.checkCancellation()
        let target = isSymbolicLink ? url.resolvingSymlinksInPath() : url
        let targetType: FileAttributeType
        do {
            targetType = isSymbolicLink ? try fileType(at: target) : originalType
        } catch {
            return FileEntry(url: url, kind: .unavailable, isSymbolicLink: isSymbolicLink)
        }
        let kind: FileEntry.Kind
        switch targetType {
        case .typeDirectory:
            kind = fileManager.isReadableFile(atPath: target.path)
                && fileManager.isExecutableFile(atPath: target.path) ? .directory : .unavailable
        case .typeRegular:
            kind = fileManager.isReadableFile(atPath: target.path) ? .file : .unavailable
        case .typeSymbolicLink:
            // Unresolved links (including cycles) cannot be entered or confirmed.
            kind = .unavailable
        default:
            kind = .other
        }
        return FileEntry(url: url, kind: kind, isSymbolicLink: isSymbolicLink)
    }

    private func fileType(at url: URL) throws -> FileAttributeType {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                throw Failure.io(underlying: NSError(
                    domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue
                ))
            }
            return type
        } catch let error as Failure {
            throw error
        } catch {
            throw failure(for: error)
        }
    }

    nonisolated static func normalizedLocation(_ url: URL) throws -> URL {
        // URL.path can discard an encoded NUL on Foundation platforms. Decode the
        // complete encoded path before validating or passing it to pathname APIs.
        guard let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              let path = encodedPath.removingPercentEncoding,
              url.isFileURL, url.baseURL == nil, path.hasPrefix("/"),
              url.host == nil || url.host == "" || url.host == "localhost",
              url.query == nil, url.fragment == nil, !path.contains("\0") else {
            throw Failure.invalidLocation
        }
        // Normalize dot components without resolving any link in the identity.
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                if !components.isEmpty { components.removeLast() }
            } else {
                components.append(component)
            }
        }
        return URL(fileURLWithPath: "/" + components.joined(separator: "/"), isDirectory: false)
    }

    private func failure(for error: any Error) -> Failure {
        let underlying = error as NSError
        if underlying.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: underlying.code) {
            case .fileNoSuchFile, .fileReadNoSuchFile: return .missing
            case .fileReadNoPermission: return .unreadable
            default: break
            }
        }
        return .io(underlying: underlying)
    }
}

extension FileDirectoryReader.Failure: Error {}

extension FileDirectoryReader.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidLocation: "Choose an absolute local file path."
        case .notDirectory: "This location is not a directory."
        case .notRegularFile: "Choose a regular file."
        case .missing: "This location no longer exists."
        case .unreadable: "This location cannot be read. Check its permissions."
        case .io(let underlying): "The location could not be inspected: \(underlying.localizedDescription)"
        }
    }
}
