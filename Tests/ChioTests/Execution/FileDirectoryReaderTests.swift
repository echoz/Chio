@testable import Chio
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct FileDirectoryReaderTests {
    @Test("Listings include every visible file type and put directories first")
    func listingAndSorting() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.directory("z-directory")
        try tree.directory("A-directory")
        try tree.file("notes.md")
        try tree.file("Archive.txt")
        try tree.file("beta.bin")
        try tree.file(".hidden-file")
        try tree.directory(".hidden-directory")
        let reader = FileDirectoryReader()

        let visible = try await reader.readDirectory(at: tree.root, showsHiddenFiles: false)
        #expect(visible.map(\.name) == ["A-directory", "z-directory", "Archive.txt", "beta.bin", "notes.md"])
        #expect(visible.map(\.kind) == [.directory, .directory, .file, .file, .file])
        #expect(visible.allSatisfy { !$0.isSymbolicLink })
        #expect(visible.map(\.url) == [tree.url("A-directory"), tree.url("z-directory"),
                                     tree.url("Archive.txt"), tree.url("beta.bin"), tree.url("notes.md")])
        // There is no extension or application filter at the loading boundary.
        #expect(visible.contains { $0.name == "beta.bin" })
        let all = try await reader.readDirectory(at: tree.root, showsHiddenFiles: true)
        #expect(all.map(\.name) == [".hidden-directory", "A-directory", "z-directory",
                                   ".hidden-file", "Archive.txt", "beta.bin", "notes.md"])
        #expect(Set(all.map(\.id)).count == 7)
    }

    @Test("Name ordering ignores case and is repeatable")
    func deterministicNameOrdering() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        // Kind independence is covered above; this fixture works on case-insensitive disks too.
        for name in ["zeta", "Beta", "alpha", "ALPINE"] { try tree.file(name) }
        let reader = FileDirectoryReader()
        let first = try await reader.readDirectory(at: tree.root, showsHiddenFiles: true)
        let second = try await reader.readDirectory(at: tree.root, showsHiddenFiles: true)
        #expect(first.map(\.name) == ["alpha", "ALPINE", "Beta", "zeta"])
        #expect(second == first)
    }

    @Test("Names equal ignoring case retain a stable tie-break",
          .enabled(if: FileDirectoryReaderTests.supportsCaseDistinctNames,
                   "This filesystem treats names differing only by case as the same file"))
    func caseTieOrdering() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.file("alpha")
        try tree.file("Alpha")
        let reader = FileDirectoryReader()
        let entries = try await reader.readDirectory(at: tree.root, showsHiddenFiles: false)
        #expect(entries.map(\.name) == ["Alpha", "alpha"])
    }

    @Test("Empty directories return an empty list")
    func emptyDirectory() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        #expect(try await FileDirectoryReader().readDirectory(at: tree.root, showsHiddenFiles: false).isEmpty)
    }

    @Test("Links retain their lexical identity while adopting the target kind")
    func symbolicLinks() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.directory("actual-directory")
        try tree.file("actual-directory/inside.txt")
        try tree.file("actual.txt")
        try tree.link("directory-link", destination: "actual-directory")
        try tree.link("file-link", destination: "actual.txt")
        try tree.link("broken-link", destination: "missing.txt")
        try tree.link("chained-link", destination: "file-link")
        let reader = FileDirectoryReader()
        let entries = try await reader.readDirectory(at: tree.root, showsHiddenFiles: false)
        let directoryLink = try #require(entries.first { $0.name == "directory-link" })
        let fileLink = try #require(entries.first { $0.name == "file-link" })
        let brokenLink = try #require(entries.first { $0.name == "broken-link" })
        #expect(directoryLink.kind == .directory)
        #expect(fileLink.kind == .file)
        #expect(brokenLink.kind == .unavailable)
        #expect([directoryLink, fileLink, brokenLink].allSatisfy { $0.isSymbolicLink })
        #expect(fileLink.url == tree.url("file-link"))
        #expect(try await reader.validateFile(at: fileLink.url) == fileLink.url)
        #expect(try await reader.validateFile(at: tree.url("chained-link")) == tree.url("chained-link"))
        let children = try await reader.readDirectory(at: directoryLink.url, showsHiddenFiles: false)
        #expect(children.map(\.url) == [tree.url("directory-link/inside.txt")])
        await expectFailure(.notRegularFile) { _ = try await reader.validateFile(at: directoryLink.url) }
        await expectFailure(.missing) { _ = try await reader.validateFile(at: brokenLink.url) }
        await expectFailure(.missing) {
            _ = try await reader.readDirectory(at: brokenLink.url, showsHiddenFiles: false)
        }
    }

    @Test("Self-referential and cyclic links stay unavailable and cannot be confirmed")
    func cyclicLinks() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.link("self-link", destination: "self-link")
        try tree.link("cycle-a", destination: "cycle-b")
        try tree.link("cycle-b", destination: "cycle-a")
        let reader = FileDirectoryReader()
        let entries = try await reader.readDirectory(at: tree.root, showsHiddenFiles: false)
        #expect(entries.map(\.name) == ["cycle-a", "cycle-b", "self-link"])
        #expect(entries.map(\.kind) == [.unavailable, .unavailable, .unavailable])
        #expect(entries.allSatisfy { $0.isSymbolicLink })
        for entry in entries {
            do {
                _ = try await reader.validateFile(at: entry.url)
                Issue.record("A cyclic link was accepted as a regular file")
            } catch let error as FileDirectoryReader.Failure {
                #expect(error.errorDescription?.isEmpty == false)
            } catch {
                Issue.record("Unexpected cyclic-link error: \(error)")
            }
        }
    }

    @Test("A linked directory may lead outside the starting directory")
    func directoryLinkTraversal() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        let outside = try TemporaryTree()
        defer { outside.remove() }
        try outside.file("outside.txt")
        try tree.link("outside", destination: outside.root.path)
        let reader = FileDirectoryReader()
        let entries = try await reader.readDirectory(at: tree.url("outside"), showsHiddenFiles: false)
        #expect(entries.map(\.name) == ["outside.txt"])
        #expect(entries.map(\.url) == [tree.url("outside/outside.txt")])
        #expect(try await reader.validateFile(at: entries[0].url) == tree.url("outside/outside.txt"))
    }

    @Test("Locations must be absolute local file URLs")
    func invalidLocations() async throws {
        let reader = FileDirectoryReader()
        let locations = [URL(string: "https://example.com/file")!,
                         URL(string: "file:relative.txt")!,
                         URL(string: "file://remote.example/file")!,
                         URL(string: "file:///tmp/file?query")!,
                         URL(string: "file:///tmp/file%00suffix")!,
                         URL(string: "child", relativeTo: URL(fileURLWithPath: "/tmp/"))!]
        for location in locations {
            await expectFailure(.invalidLocation, context: location.absoluteString) {
                _ = try await reader.readDirectory(at: location, showsHiddenFiles: false)
            }
            await expectFailure(.invalidLocation, context: location.absoluteString) {
                _ = try await reader.validateFile(at: location)
            }
        }
    }

    @Test("Encoded NUL paths are rejected before inspecting an existing prefix")
    func encodedNulLocation() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.file("candidate")
        let malformed = URL(string: tree.url("candidate").absoluteString + "%00suffix")!
        let reader = FileDirectoryReader()
        await expectFailure(.invalidLocation) { _ = try await reader.validateFile(at: malformed) }
        await expectFailure(.invalidLocation) {
            _ = try await reader.readDirectory(at: malformed, showsHiddenFiles: false)
        }
        // A percent sequence in a real filename remains a literal filename.
        try tree.file("candidate%00suffix")
        let literal = tree.url("candidate%00suffix")
        #expect(try await reader.validateFile(at: literal) == literal)
    }

    @Test("Dot paths normalize lexically without replacing a link with its target")
    func lexicalNormalization() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.file("actual.txt")
        try tree.link("file-link", destination: "actual.txt")
        let reader = FileDirectoryReader()
        let unnormalized = URL(string: tree.root.absoluteString + "/./unused/../file-link")!
        #expect(try await reader.validateFile(at: unnormalized) == tree.url("file-link"))
        let unnormalizedDirectory = URL(string: tree.root.absoluteString + "/./unused/..")!
        let entries = try await reader.readDirectory(at: unnormalizedDirectory, showsHiddenFiles: false)
        #expect(entries.map(\.url) == [tree.url("actual.txt"), tree.url("file-link")])
    }

    @Test("Validation rejects missing locations and files changed into directories")
    func freshnessAndKinds() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.file("candidate.txt")
        let reader = FileDirectoryReader()
        let candidate = tree.url("candidate.txt")
        #expect(try await reader.validateFile(at: candidate) == candidate)
        await expectFailure(.notDirectory) {
            _ = try await reader.readDirectory(at: candidate, showsHiddenFiles: false)
        }
        try FileManager.default.removeItem(at: candidate)
        await expectFailure(.missing) { _ = try await reader.validateFile(at: candidate) }
        await expectFailure(.missing) {
            _ = try await reader.readDirectory(at: candidate, showsHiddenFiles: false)
        }
        try tree.directory("candidate.txt")
        await expectFailure(.notRegularFile) { _ = try await reader.validateFile(at: candidate) }
    }

    @Test("Confirmation rechecks a link whose target changed")
    func changedLinkTarget() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.file("actual.txt")
        try tree.link("file-link", destination: "actual.txt")
        let reader = FileDirectoryReader()
        #expect(try await reader.validateFile(at: tree.url("file-link")) == tree.url("file-link"))
        try FileManager.default.removeItem(at: tree.url("actual.txt"))
        try tree.directory("actual.txt")
        await expectFailure(.notRegularFile) { _ = try await reader.validateFile(at: tree.url("file-link")) }
    }

    #if canImport(Darwin) || canImport(Glibc)
    @Test("Special files stay visible but cannot be confirmed")
    func specialFiles() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        #expect(mkfifo(tree.url("pipe").path, 0o600) == 0)
        try tree.link("pipe-link", destination: "pipe")
        let reader = FileDirectoryReader()
        let entries = try await reader.readDirectory(at: tree.root, showsHiddenFiles: false)
        #expect(entries.map(\.name) == ["pipe", "pipe-link"])
        #expect(entries.map(\.kind) == [.other, .other])
        #expect(entries.map(\.isSymbolicLink) == [false, true])
        for entry in entries {
            await expectFailure(.notRegularFile) { _ = try await reader.validateFile(at: entry.url) }
        }
    }
    #endif

    @Test("Permission failures remain unavailable and prevent confirmation",
          .enabled(if: FileDirectoryReaderTests.enforcesReadPermissions,
                   "This environment does not enforce removal of file read permission"))
    func permissionDenied() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.file("locked-file")
        try tree.directory("locked-directory")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: tree.url("locked-file").path)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: tree.url("locked-directory").path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tree.url("locked-directory").path)
        }
        let reader = FileDirectoryReader()
        let entries = try await reader.readDirectory(at: tree.root, showsHiddenFiles: false)
        #expect(entries.map(\.name) == ["locked-directory", "locked-file"])
        #expect(entries.map(\.kind) == [.unavailable, .unavailable])
        await expectFailure(.unreadable) { _ = try await reader.validateFile(at: tree.url("locked-file")) }
        await expectFailure(.unreadable) {
            _ = try await reader.readDirectory(at: tree.url("locked-directory"), showsHiddenFiles: false)
        }
    }

    #if canImport(Darwin)
    @Test("Filesystem hidden flags are respected in addition to dot names")
    func hiddenFlag() async throws {
        let tree = try TemporaryTree()
        defer { tree.remove() }
        try tree.file("hidden-by-flag")
        var location = tree.url("hidden-by-flag")
        var values = URLResourceValues()
        values.isHidden = true
        try location.setResourceValues(values)
        let reader = FileDirectoryReader()
        #expect(try await reader.readDirectory(at: tree.root, showsHiddenFiles: false).isEmpty)
        #expect(try await reader.readDirectory(at: tree.root, showsHiddenFiles: true).map(\.name) == ["hidden-by-flag"])
    }
    #endif

    @Test("Cancelled callers stop before attempting filesystem work")
    func cancellation() async throws {
        let reader = FileDirectoryReader()
        let invalid = URL(string: "https://example.com/file")!
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await reader.readDirectory(at: invalid, showsHiddenFiles: false)
                Issue.record("A cancelled directory read succeeded")
            } catch is CancellationError {
            } catch {
                Issue.record("Expected cancellation before location validation, received \(error)")
            }
            do {
                _ = try await reader.validateFile(at: invalid)
                Issue.record("A cancelled validation succeeded")
            } catch is CancellationError {
            } catch {
                Issue.record("Expected cancellation before location validation, received \(error)")
            }
        }
        await task.value
    }

    @Test("Entries are immutable observations with URL identity and lossless coding")
    func entryValues() throws {
        for kind in [FileEntry.Kind.directory, .file, .other, .unavailable] {
            for isLink in [false, true] {
                let original = FileEntry(url: URL(fileURLWithPath: "/tmp/name.txt"), kind: kind, isSymbolicLink: isLink)
                let encoded = try JSONEncoder().encode(original)
                let decoded = try JSONDecoder().decode(FileEntry.self, from: encoded)
                #expect(decoded == original)
                #expect(decoded.id == original.url)
                #expect(decoded.name == "name.txt")
                #expect(Set([original, decoded]).count == 1)
            }
        }
    }

    private static var enforcesReadPermissions: Bool {
        guard let tree = try? TemporaryTree() else { return false }
        defer { tree.remove() }
        do {
            try tree.file("probe")
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: tree.url("probe").path)
            return !FileManager.default.isReadableFile(atPath: tree.url("probe").path)
        } catch {
            return false
        }
    }

    private static var supportsCaseDistinctNames: Bool {
        guard let tree = try? TemporaryTree() else { return false }
        defer { tree.remove() }
        do {
            try tree.file("probe")
            try tree.file("PROBE")
            return try FileManager.default.contentsOfDirectory(atPath: tree.root.path).count == 2
        } catch {
            return false
        }
    }

    private func expectFailure(
        _ expected: FileDirectoryReader.Failure,
        context: String = "",
        sourceLocation: SourceLocation = #_sourceLocation,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected a filesystem failure for \(context)", sourceLocation: sourceLocation)
        } catch let actual as FileDirectoryReader.Failure {
            switch (actual, expected) {
            case (.invalidLocation, .invalidLocation), (.notDirectory, .notDirectory),
                 (.notRegularFile, .notRegularFile), (.missing, .missing),
                 (.unreadable, .unreadable), (.io, .io):
                break
            default:
                Issue.record("Expected \(expected), received \(actual) for \(context)", sourceLocation: sourceLocation)
            }
            #expect(actual.errorDescription?.isEmpty == false, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }

    private struct TemporaryTree {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("chio-file-reader-\(UUID().uuidString)", isDirectory: false)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        }

        func url(_ name: String) -> URL {
            URL(fileURLWithPath: root.path + "/" + name, isDirectory: false)
        }

        func directory(_ name: String) throws {
            try FileManager.default.createDirectory(at: url(name), withIntermediateDirectories: false)
        }

        func file(_ name: String) throws {
            try Data("fixture".utf8).write(to: url(name))
        }

        func link(_ name: String, destination: String) throws {
            try FileManager.default.createSymbolicLink(atPath: url(name).path, withDestinationPath: destination)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
