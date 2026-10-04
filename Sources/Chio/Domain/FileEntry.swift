import Foundation

/// A filesystem observation. Eligibility is rechecked before confirmation.
struct FileEntry {
    enum Kind {
        case directory
        case file
        case other
        case unavailable
    }

    let url: URL
    let kind: Kind
    let isSymbolicLink: Bool

    var name: String { url.lastPathComponent }
}

extension FileEntry: Identifiable {
    var id: URL { url }
}

extension FileEntry: Hashable {}
extension FileEntry: Codable {}
extension FileEntry: Sendable {}

extension FileEntry.Kind: Hashable {}
extension FileEntry.Kind: Codable {}
extension FileEntry.Kind: Sendable {}
