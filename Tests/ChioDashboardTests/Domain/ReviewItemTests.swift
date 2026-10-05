@testable import ChioDashboard
import Foundation
import Testing

struct ReviewItemTests {
    @Test("Recent ordering uses newest update then ascending identity")
    func recentOrdering() {
        let items = [item(9, "Tools", 100), item(8, "Chio", 200), item(3, "SwiftTUI", 200)]
        let original = items

        #expect(ReviewItem.ordered(items, by: .recent).map(\.id) == [3, 8, 9])
        #expect(items == original)
        #expect(ReviewItem.ordered([], by: .recent).isEmpty)
    }

    @Test("Repository ordering groups names then uses update and identity")
    func repositoryOrdering() {
        let items = [
            item(1, "Tools", 300), item(9, "Chio", 100), item(8, "Chio", 200),
            item(3, "Chio", 200), item(2, "SwiftTUI", 400),
        ]
        let original = items

        #expect(ReviewItem.ordered(items, by: .repository).map(\.id) == [3, 8, 9, 2, 1])
        #expect(items == original)
    }

    @Test("Search includes the review title, repository, author and identity")
    func searchableMetadata() {
        let review = item(214, "Chio", 100)

        #expect(review.searchText.contains("Keep selection"))
        #expect(review.searchText.contains("Chio"))
        #expect(review.searchText.contains("maya"))
        #expect(review.searchText.contains("214"))
    }

    @Test("Local examples have stable unique identities and varied review states")
    func exampleCoverage() {
        let examples = ReviewItem.examples

        #expect(examples.count == 16)
        #expect(Set(examples.map(\.id)).count == examples.count)
        #expect(Set(examples.map(\.repository)) == ["Chio", "SwiftTUI", "Tools"])
        #expect(examples.filter { $0.status == .draft }.count == 4)
        #expect(examples.filter { $0.status == .changesRequested }.count == 3)
        #expect(examples.contains { $0.status == .review })
        #expect(examples.allSatisfy { !$0.summary.isEmpty && !$0.files.isEmpty })
        #expect(examples.contains { $0.summary.contains("```swift") })
        #expect(examples.first?.updatedAt == Date(timeIntervalSince1970: 1_791_216_000))
    }

    @Test("Review snapshots retain every field when encoded and decoded")
    func codingRoundTrip() throws {
        let original = ReviewItem.examples
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([ReviewItem].self, from: encoded)

        #expect(decoded == original)
        #expect(Set(decoded).count == original.count)
    }

    private func item(_ id: Int, _ repository: String, _ epoch: TimeInterval) -> ReviewItem {
        ReviewItem(id: id, title: "Keep selection", repository: repository, author: "maya",
                   status: .review, updatedAt: Date(timeIntervalSince1970: epoch),
                   summary: "## Review\n\nKeep the selected identity.", files: ["Sources/List.swift"])
    }
}
