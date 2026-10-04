/// How a searchable list matches its query against each item's searchable text.
public enum SearchFilter {
    /// Matches query characters in order and ranks compact, early matches first.
    case fuzzy
    /// Matches contiguous text, preserving the original item order.
    case substring
}

extension SearchFilter: Equatable {}
extension SearchFilter: Hashable {}
extension SearchFilter: Sendable {}
extension SearchFilter: Codable {}
