/// A checked page position and item window in a finite collection.
///
/// Page indices and item ranges are zero-based. Empty collections have no page.
public struct Pagination {
    public let totalCount: Int
    public let pageSize: Int
    public let pageIndex: Int?

    /// Starts on the first page, or no page when the collection is empty.
    ///
    /// Programmer inputs must have a nonnegative count and a positive page size.
    public init(totalCount: Int, pageSize: Int) {
        self.init(totalCount: totalCount, pageSize: pageSize,
                  pageIndex: totalCount == 0 ? nil : 0)
    }

    private init(totalCount: Int, pageSize: Int, pageIndex: Int?) {
        precondition(Self.validationIssue(totalCount: totalCount, pageSize: pageSize,
                                         pageIndex: pageIndex) == nil,
                     "Pagination requires a nonnegative count, positive page size, and valid page index")
        self.totalCount = totalCount
        self.pageSize = pageSize
        self.pageIndex = pageIndex
    }

    public var pageCount: Int {
        totalCount / pageSize + (totalCount % pageSize == 0 ? 0 : 1)
    }

    /// The visible zero-based item range; an empty collection returns `0..<0`.
    public var itemRange: Range<Int> {
        guard let pageIndex else { return 0..<0 }
        let start = pageIndex * pageSize
        return start..<(start + min(pageSize, totalCount - start))
    }

    public var canGoBack: Bool { pageIndex.map { $0 > 0 } ?? false }

    public var canGoForward: Bool { pageIndex.map { $0 < pageCount - 1 } ?? false }

    /// Selects an existing page, rejecting indices outside the current collection.
    public func selectingPage(at index: Int) -> Self? {
        guard index >= 0, index < pageCount else { return nil }
        return Pagination(totalCount: totalCount, pageSize: pageSize, pageIndex: index)
    }

    public func movingToFirstPage() -> Self {
        guard pageIndex != nil else { return self }
        return Pagination(totalCount: totalCount, pageSize: pageSize, pageIndex: 0)
    }

    public func movingToPreviousPage() -> Self {
        guard canGoBack, let pageIndex else { return self }
        return Pagination(totalCount: totalCount, pageSize: pageSize, pageIndex: pageIndex - 1)
    }

    public func movingToNextPage() -> Self {
        guard canGoForward, let pageIndex else { return self }
        return Pagination(totalCount: totalCount, pageSize: pageSize, pageIndex: pageIndex + 1)
    }

    public func movingToLastPage() -> Self {
        guard pageIndex != nil else { return self }
        return Pagination(totalCount: totalCount, pageSize: pageSize, pageIndex: pageCount - 1)
    }

    /// Keeps the current index when possible, otherwise selects the last page.
    /// Empty-to-nonempty updates start on the first page. The count must be nonnegative.
    public func updatingTotalCount(to count: Int) -> Self {
        precondition(count >= 0, "Pagination total count must be nonnegative")
        let index = count == 0 ? nil : min(pageIndex ?? 0, (count - 1) / pageSize)
        return Pagination(totalCount: count, pageSize: pageSize, pageIndex: index)
    }

    /// Selects the new page containing the old first visible item.
    /// The new page size must be positive.
    public func resizingPages(to size: Int) -> Self {
        precondition(size > 0, "Pagination page size must be positive")
        let index = pageIndex == nil ? nil : itemRange.lowerBound / size
        return Pagination(totalCount: totalCount, pageSize: size, pageIndex: index)
    }

    private enum CodingKeys: String, CodingKey {
        case totalCount, pageSize, pageIndex
    }

    private static func validationIssue(
        totalCount: Int, pageSize: Int, pageIndex: Int?
    ) -> (key: CodingKeys, description: String)? {
        guard totalCount >= 0 else { return (.totalCount, "Total count must be nonnegative") }
        guard pageSize > 0 else { return (.pageSize, "Page size must be positive") }
        if totalCount == 0 {
            return pageIndex == nil ? nil : (.pageIndex, "An empty collection cannot have a page index")
        }
        guard let pageIndex else { return (.pageIndex, "A nonempty collection requires a page index") }
        guard pageIndex >= 0, pageIndex <= (totalCount - 1) / pageSize else {
            return (.pageIndex, "Page index must identify an existing page")
        }
        return nil
    }
}

extension Pagination: Hashable {}

extension Pagination: Sendable {}

extension Pagination: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalCount, forKey: .totalCount)
        try container.encode(pageSize, forKey: .pageSize)
        if let pageIndex {
            try container.encode(pageIndex, forKey: .pageIndex)
        } else {
            try container.encodeNil(forKey: .pageIndex)
        }
    }
}

extension Pagination: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let totalCount = try container.decode(Int.self, forKey: .totalCount)
        let pageSize = try container.decode(Int.self, forKey: .pageSize)
        let pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex)
        if let issue = Self.validationIssue(totalCount: totalCount, pageSize: pageSize,
                                             pageIndex: pageIndex) {
            throw DecodingError.dataCorruptedError(forKey: issue.key, in: container,
                                                   debugDescription: issue.description)
        }
        self.init(totalCount: totalCount, pageSize: pageSize, pageIndex: pageIndex)
    }
}
