import Foundation

/// Pure matching rules, independent of rendering, selection, and activation.
enum SearchMatcher {
    static func filtered<Item>(
        _ items: [Item],
        query: String,
        filter: SearchFilter,
        searchText: (Item) -> String
    ) -> [Item] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return items }

        switch filter {
        case .substring:
            return items.filter { normalized(searchText($0)).contains(needle) }
        case .fuzzy:
            let ranked = items.enumerated().compactMap { index, item in
                score(query: Array(needle), text: Array(normalized(searchText(item))))
                    .map { (item: item, score: $0, index: index) }
            }
            return ranked.sorted {
                $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score
            }.map(\.item)
        }
    }

    static func score(query: String, text: String) -> Int? {
        score(query: Array(normalized(query)), text: Array(normalized(text)))
    }

    /// Fixed locale prevents the host's locale from changing result order.
    /// Folding and Character indexing handle accents and complete graphemes.
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Dynamic programming finds the best subsequence in O(query × text) time
    /// and O(text) space. Adjacent letters and word starts receive bonuses;
    /// skipped characters and long tails receive small penalties.
    private static func score(query: [Character], text: [Character]) -> Int? {
        guard !query.isEmpty else { return 0 }
        guard query.count <= text.count else { return nil }

        var previous = [Int?](repeating: nil, count: text.count)
        for queryIndex in query.indices {
            var current = [Int?](repeating: nil, count: text.count)
            var bestSeparated: Int?
            for textIndex in text.indices {
                if textIndex >= 2, let preceding = previous[textIndex - 2] {
                    let candidate = preceding + textIndex - 2
                    bestSeparated = max(bestSeparated ?? candidate, candidate)
                }
                guard text[textIndex] == query[queryIndex] else { continue }
                let isWordStart = textIndex == 0
                    || (!text[textIndex - 1].isLetter && !text[textIndex - 1].isNumber)
                let characterScore = 10 + (isWordStart ? 12 : 0)
                if queryIndex == 0 {
                    current[textIndex] = characterScore - textIndex
                    continue
                }
                var predecessor = bestSeparated.map { $0 - (textIndex - 1) }
                if textIndex > 0, let adjacent = previous[textIndex - 1] {
                    let candidate = adjacent + 18
                    predecessor = max(predecessor ?? candidate, candidate)
                }
                current[textIndex] = predecessor.map { $0 + characterScore }
            }
            previous = current
        }
        return previous.enumerated().compactMap { index, value in
            value.map { $0 - (text.count - index - 1) }
        }.max()
    }
}
