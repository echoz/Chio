import Chio
import Foundation
import Testing

struct PaginationTests {
    @Test("Empty collections have no page and every movement is inert")
    func emptyCollection() {
        let empty = Pagination(totalCount: 0, pageSize: 5)
        #expect(empty.pageIndex == nil)
        #expect(empty.pageCount == 0)
        #expect(empty.itemRange == 0..<0)
        #expect(!empty.canGoBack && !empty.canGoForward)
        #expect(empty.selectingPage(at: 0) == nil)
        #expect(empty.movingToFirstPage() == empty)
        #expect(empty.movingToPreviousPage() == empty)
        #expect(empty.movingToNextPage() == empty)
        #expect(empty.movingToLastPage() == empty)
        #expect(empty.resizingPages(to: 1).pageIndex == nil)
    }

    @Test("One page retains its exact item range", arguments: [1, 5])
    func singlePage(count: Int) {
        let page = Pagination(totalCount: count, pageSize: 5)
        #expect(page.pageIndex == 0)
        #expect(page.pageCount == 1)
        #expect(page.itemRange == 0..<count)
        #expect(!page.canGoBack && !page.canGoForward)
        #expect(page.selectingPage(at: 0) == page)
        #expect(page.movingToFirstPage() == page)
        #expect(page.movingToPreviousPage() == page)
        #expect(page.movingToNextPage() == page)
        #expect(page.movingToLastPage() == page)
    }

    @Test("Navigation has independent full and partial page bounds")
    func pageBounds() throws {
        let first = Pagination(totalCount: 12, pageSize: 5)
        let middle = first.movingToNextPage()
        let last = middle.movingToNextPage()
        #expect(first.pageCount == 3)
        #expect(first.pageIndex == 0 && first.itemRange == 0..<5)
        #expect(!first.canGoBack && first.canGoForward)
        #expect(middle.pageIndex == 1 && middle.itemRange == 5..<10)
        #expect(middle.canGoBack && middle.canGoForward)
        #expect(last.pageIndex == 2 && last.itemRange == 10..<12)
        #expect(last.canGoBack && !last.canGoForward)
        #expect(last.movingToNextPage() == last)
        #expect(first.movingToPreviousPage() == first)
        #expect(last.movingToPreviousPage() == middle)
        #expect(last.movingToFirstPage() == first)
        #expect(first.movingToLastPage() == last)
        #expect(try #require(first.selectingPage(at: 1)) == middle)
        #expect(first == Pagination(totalCount: 12, pageSize: 5))
        #expect(Pagination(totalCount: 10, pageSize: 5).movingToLastPage().itemRange == 5..<10)
    }

    @Test("Rejected selection leaves the original unchanged", arguments: [-1, 3, Int.max])
    func rejectedSelection(index: Int) {
        let original = Pagination(totalCount: 12, pageSize: 5).movingToNextPage()
        #expect(original.selectingPage(at: index) == nil)
        #expect(original.pageIndex == 1)
        #expect(original.itemRange == 5..<10)
    }

    @Test("Count changes retain a valid index or choose the last remaining page")
    func countChanges() {
        let original = Pagination(totalCount: 12, pageSize: 5).movingToLastPage()
        let grown = original.updatingTotalCount(to: 30)
        #expect(grown.totalCount == 30 && grown.pageIndex == 2)
        #expect(grown.pageCount == 6 && grown.itemRange == 10..<15)
        let retained = original.updatingTotalCount(to: 11)
        #expect(retained.pageIndex == 2 && retained.itemRange == 10..<11)
        let clamped = original.updatingTotalCount(to: 6)
        #expect(clamped.pageIndex == 1 && clamped.itemRange == 5..<6)
        let single = original.updatingTotalCount(to: 1)
        #expect(single.pageIndex == 0 && single.itemRange == 0..<1)
        let empty = original.updatingTotalCount(to: 0)
        #expect(empty.pageIndex == nil && empty.itemRange == 0..<0)
        let restored = empty.updatingTotalCount(to: 8)
        #expect(restored.pageIndex == 0 && restored.itemRange == 0..<5)
        #expect(original.totalCount == 12 && original.pageIndex == 2)
        #expect(original.updatingTotalCount(to: 12) == original)
    }

    @Test("Page resizing retains the old first item within the new page")
    func pageSizeChanges() {
        let original = Pagination(totalCount: 23, pageSize: 5).movingToNextPage().movingToNextPage()
        let smaller = original.resizingPages(to: 3)
        #expect(smaller.pageSize == 3 && smaller.pageIndex == 3)
        #expect(smaller.itemRange == 9..<12)
        let larger = original.resizingPages(to: 8)
        #expect(larger.pageSize == 8 && larger.pageIndex == 1)
        #expect(larger.itemRange == 8..<16)
        let entire = original.resizingPages(to: 30)
        #expect(entire.pageIndex == 0 && entire.itemRange == 0..<23)
        let tail = original.movingToLastPage().resizingPages(to: 7)
        #expect(tail.pageIndex == 2 && tail.itemRange == 14..<21)
        #expect(original.pageSize == 5 && original.itemRange == 10..<15)
        #expect(original.resizingPages(to: 5) == original)
    }

    @Test("Maximum integer counts and sizes do not overflow")
    func maximumIntegers() throws {
        let units = Pagination(totalCount: Int.max, pageSize: 1)
        #expect(units.pageCount == Int.max)
        let lastUnit = units.movingToLastPage()
        #expect(lastUnit.pageIndex == Int.max - 1)
        #expect(lastUnit.itemRange == (Int.max - 1)..<Int.max)
        #expect(lastUnit.movingToNextPage() == lastUnit)
        #expect(units.selectingPage(at: Int.max) == nil)
        #expect(lastUnit.resizingPages(to: Int.max).itemRange == 0..<Int.max)
        let thirds = Pagination(totalCount: Int.max, pageSize: Int.max / 2)
        #expect(thirds.pageCount == 3)
        #expect(thirds.movingToLastPage().itemRange == (Int.max - 1)..<Int.max)
        let pair = Pagination(totalCount: Int.max, pageSize: Int.max - 1)
        #expect(pair.pageCount == 2)
        #expect(pair.movingToLastPage().itemRange == (Int.max - 1)..<Int.max)
        let full = Pagination(totalCount: Int.max, pageSize: Int.max)
        #expect(full.pageCount == 1 && full.itemRange == 0..<Int.max)
        let decoded = try JSONDecoder().decode(Pagination.self, from: JSONEncoder().encode(lastUnit))
        #expect(decoded == lastUnit)
    }

    @Test("Programmer inputs enforce construction and replacement preconditions", arguments: 0..<5)
    func invalidProgrammerInputs(input: Int) async {
        await #expect(processExitsWith: .failure) { [input] in
            switch input {
            case 0: _ = Pagination(totalCount: -1, pageSize: 5)
            case 1: _ = Pagination(totalCount: 1, pageSize: 0)
            case 2: _ = Pagination(totalCount: 0, pageSize: -1)
            case 3: _ = Pagination(totalCount: 5, pageSize: 2).updatingTotalCount(to: -1)
            default: _ = Pagination(totalCount: 5, pageSize: 2).resizingPages(to: 0)
            }
        }
    }

    @Test("Coding retains page position and encodes the empty page as null")
    func coding() throws {
        let positioned = Pagination(totalCount: 12, pageSize: 5).movingToLastPage()
        let fixture = Data(#"{"totalCount":12,"pageSize":5,"pageIndex":2}"#.utf8)
        #expect(try JSONDecoder().decode(Pagination.self, from: fixture) == positioned)
        #expect(try JSONDecoder().decode(Pagination.self, from: JSONEncoder().encode(positioned)) == positioned)
        #expect(Set([positioned, positioned.movingToLastPage()]).count == 1)
        #expect(Set([positioned, positioned.movingToFirstPage()]).count == 2)
        let empty = Pagination(totalCount: 0, pageSize: 5)
        let encoded = try JSONEncoder().encode(empty)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["totalCount", "pageSize", "pageIndex"])
        #expect(object["pageIndex"] is NSNull)
        #expect(try JSONDecoder().decode(Pagination.self, from: encoded) == empty)
        #expect(try JSONDecoder().decode(Pagination.self,
                                        from: Data(#"{"totalCount":0,"pageSize":5}"#.utf8)) == empty)
    }

    @Test("Malformed pagination values decode with field errors rather than trapping", arguments: [
        (#"{"totalCount":-1,"pageSize":5,"pageIndex":0}"#, "totalCount"),
        (#"{"totalCount":5,"pageSize":0,"pageIndex":0}"#, "pageSize"),
        (#"{"totalCount":0,"pageSize":-1,"pageIndex":null}"#, "pageSize"),
        (#"{"totalCount":5,"pageSize":2}"#, "pageIndex"),
        (#"{"totalCount":5,"pageSize":2,"pageIndex":null}"#, "pageIndex"),
        (#"{"totalCount":5,"pageSize":2,"pageIndex":-1}"#, "pageIndex"),
        (#"{"totalCount":5,"pageSize":2,"pageIndex":3}"#, "pageIndex"),
        (#"{"totalCount":0,"pageSize":2,"pageIndex":0}"#, "pageIndex"),
    ])
    func malformedInvariants(fixture: String, field: String) throws {
        do {
            _ = try JSONDecoder().decode(Pagination.self, from: Data(fixture.utf8))
            Issue.record("Malformed pagination unexpectedly decoded")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.codingPath.map(\.stringValue) == [field])
        }
    }

    @Test("Missing required fields and wrong JSON types are rejected", arguments: [
        #"{"pageSize":2,"pageIndex":0}"#,
        #"{"totalCount":5,"pageIndex":0}"#,
        #"{"totalCount":"5","pageSize":2,"pageIndex":0}"#,
        #"{"totalCount":5,"pageSize":2,"pageIndex":"0"}"#,
        #"{"totalCount":5,"pageSize":2.5,"pageIndex":0}"#,
    ])
    func malformedShape(fixture: String) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Pagination.self, from: Data(fixture.utf8))
        }
    }
}
