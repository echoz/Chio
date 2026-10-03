import Testing
@testable import Chio

@Suite("Search matching")
struct SearchMatcherTests {
    private struct Item: Identifiable {
        let id: Int
        let name: String
    }

    @Test("Empty queries preserve all items and source order")
    func emptyQueryPreservesOrder() {
        let items = [Item(id: 3, name: "Zulu"), Item(id: 1, name: "Alpha")]
        for filter in [SearchFilter.fuzzy, .substring] {
            let result = SearchMatcher.filtered(items, query: "", filter: filter, searchText: \.name)
            #expect(result.map(\.id) == [3, 1])
        }
        #expect(SearchMatcher.score(query: "", text: "") == 0)
    }

    @Test("Fuzzy matches subsequences in order")
    func fuzzyMatchesInOrder() {
        #expect(SearchMatcher.score(query: "agt", text: "Agent") != nil)
        #expect(SearchMatcher.score(query: "tga", text: "Agent") == nil)
        #expect(SearchMatcher.score(query: "zz", text: "Agent") == nil)
        #expect(SearchMatcher.score(query: "agents", text: "Agent") == nil)
    }

    @Test("Adjacent matches rank ahead of scattered matches")
    func compactMatchesRankFirst() {
        let items = [Item(id: 1, name: "a x b x c"), Item(id: 2, name: "abc")]
        let result = SearchMatcher.filtered(items, query: "abc", filter: .fuzzy, searchText: \.name)
        #expect(result.map(\.id) == [2, 1])
    }

    @Test("The best subsequence can start after an earlier matching character")
    func choosesBestSubsequence() throws {
        let laterContiguous = try #require(SearchMatcher.score(query: "abc", text: "a---abc"))
        let scattered = try #require(SearchMatcher.score(query: "abc", text: "a---b-c"))
        #expect(laterContiguous > scattered)
    }

    @Test("Equal scores preserve source order with stable identities")
    func tiesPreserveOrder() {
        let items = [Item(id: 42, name: "Agent"), Item(id: 7, name: "Agent"), Item(id: 9, name: "Other")]
        let result = SearchMatcher.filtered(items, query: "agt", filter: .fuzzy, searchText: \.name)
        #expect(result.map(\.id) == [42, 7])
    }

    @Test("Substring mode requires contiguous text and preserves source order")
    func substringMode() {
        let items = [Item(id: 1, name: "Cartography"), Item(id: 2, name: "Art"), Item(id: 3, name: "a--r--t")]
        let result = SearchMatcher.filtered(items, query: "ART", filter: .substring, searchText: \.name)
        #expect(result.map(\.id) == [1, 2])
    }

    @Test("Matching is case and accent insensitive for either filter")
    func caseAndAccents() {
        let items = [Item(id: 1, name: "CAFÉ"), Item(id: 2, name: "Cafe\u{301}"), Item(id: 3, name: "Tea")]
        for filter in [SearchFilter.fuzzy, .substring] {
            let result = SearchMatcher.filtered(items, query: "cafe", filter: filter, searchText: \.name)
            #expect(result.map(\.id) == [1, 2])
        }
    }

    @Test("Unicode graphemes, non-Latin text, and emoji remain whole")
    func unicodeText() {
        #expect(SearchMatcher.score(query: "東京", text: "東京のエージェント") != nil)
        #expect(SearchMatcher.score(query: "👨‍👩‍👧‍👦", text: "Family 👨‍👩‍👧‍👦") != nil)
        #expect(SearchMatcher.score(query: "👍🏽", text: "Done 👍🏽") != nil)
        #expect(SearchMatcher.score(query: "👨‍👩‍👧‍👦", text: "Family 👨") == nil)
    }

    @Test("No matches and empty data produce no results")
    func emptyResults() {
        let items = [Item(id: 1, name: "Agent")]
        for filter in [SearchFilter.fuzzy, .substring] {
            #expect(SearchMatcher.filtered(items, query: "zz", filter: filter, searchText: \.name).isEmpty)
            #expect(SearchMatcher.filtered([Item](), query: "a", filter: filter, searchText: \.name).isEmpty)
        }
    }
}
