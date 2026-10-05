/// Which filename extensions a file picker permits. Directories remain available
/// for navigation independently of this filter.
public enum FileExtensionFilter {
    /// Allows every regular file, including files without an extension.
    case all
    /// Matches extensions case-insensitively, without a leading dot.
    /// An empty set allows no files; an empty string matches extensionless files.
    case only(Set<String>)

    func allows(_ pathExtension: String) -> Bool {
        switch self {
        case .all: true
        case .only(let extensions):
            extensions.contains { $0.lowercased() == pathExtension.lowercased() }
        }
    }
}

extension FileExtensionFilter: Equatable {}
extension FileExtensionFilter: Hashable {}
extension FileExtensionFilter: Codable {}
extension FileExtensionFilter: Sendable {}
