/// A checked local diff snapshot; source acquisition belongs to the application.
struct DiffFile {
    let id: String
    let change: Change
    let content: Content

    init(id: String, change: Change, content: Content) throws {
        guard !id.isEmpty else { throw ValidationError.emptyIdentity }
        switch change {
        case .modified(let path), .added(let path), .deleted(let path):
            guard !path.isEmpty else { throw ValidationError.emptyPath }
        case .renamed(let from, let to):
            guard !from.isEmpty, !to.isEmpty else { throw ValidationError.emptyPath }
        }
        switch content {
        case .binary: break
        case .text(let hunks):
            var oldEnd = 0
            var newEnd = 0
            for hunk in hunks {
                switch change {
                case .added:
                    guard hunk.oldOffset == 0, hunk.oldCount == 0 else {
                        throw ValidationError.inconsistentSide
                    }
                case .deleted:
                    guard hunk.newOffset == 0, hunk.newCount == 0 else {
                        throw ValidationError.inconsistentSide
                    }
                case .modified, .renamed:
                    break
                }
                guard hunk.oldOffset >= oldEnd, hunk.newOffset >= newEnd else {
                    throw ValidationError.overlappingHunks
                }
                guard hunk.oldOffset - oldEnd == hunk.newOffset - newEnd else {
                    throw ValidationError.inconsistentHunkGaps
                }
                oldEnd = hunk.oldOffset + hunk.oldCount
                newEnd = hunk.newOffset + hunk.newCount
            }
        }
        self.id = id
        self.change = change
        self.content = content
    }

    var path: String {
        switch change {
        case .modified(let path), .added(let path), .deleted(let path): path
        case .renamed(_, let to): to
        }
    }

    var hunks: [Hunk] {
        switch content {
        case .text(let hunks): hunks
        case .binary: []
        }
    }

    var addedLineCount: Int {
        hunks.reduce(0) { count, hunk in
            count + hunk.blocks.reduce(0) { count, block in
                switch block {
                case .change(_, let added): count + added.count
                case .context: count
                }
            }
        }
    }

    var removedLineCount: Int {
        hunks.reduce(0) { count, hunk in
            count + hunk.blocks.reduce(0) { count, block in
                switch block {
                case .change(let removed, _): count + removed.count
                case .context: count
                }
            }
        }
    }

    enum Change {
        case modified(path: String)
        case added(path: String)
        case deleted(path: String)
        case renamed(from: String, to: String)
    }

    enum Content {
        case text([Hunk])
        case binary
    }

    enum Block {
        case context(String)
        case change(removed: [String], added: [String])
    }

    struct Line {
        let number: Int
        let text: String
    }

    enum UnifiedRow {
        case context(old: Line, new: Line)
        case removed(Line)
        case added(Line)
    }

    enum SplitRow {
        case context(old: Line, new: Line)
        case replacement(old: Line, new: Line)
        case removed(Line)
        case added(Line)
    }

    struct Hunk {
        /// Zero-based counts of source lines preceding this hunk on each side.
        let oldOffset: Int
        let newOffset: Int
        let blocks: [Block]

        init(oldOffset: Int, newOffset: Int, blocks: [Block]) throws {
            guard oldOffset >= 0, newOffset >= 0 else { throw ValidationError.negativeOffset }
            guard !blocks.isEmpty else { throw ValidationError.emptyHunk }
            var oldEnd = oldOffset
            var newEnd = newOffset
            for block in blocks {
                let oldCount: Int
                let newCount: Int
                let texts: [String]
                switch block {
                case .context(let text):
                    oldCount = 1
                    newCount = 1
                    texts = [text]
                case .change(let removed, let added):
                    guard !removed.isEmpty || !added.isEmpty else { throw ValidationError.emptyChange }
                    oldCount = removed.count
                    newCount = added.count
                    texts = removed + added
                }
                guard texts.allSatisfy({ !$0.contains(where: \.isNewline) }) else {
                    throw ValidationError.multilineText
                }
                let oldAdvance = oldEnd.addingReportingOverflow(oldCount)
                let newAdvance = newEnd.addingReportingOverflow(newCount)
                guard !oldAdvance.overflow, !newAdvance.overflow else {
                    throw ValidationError.lineNumberOverflow
                }
                oldEnd = oldAdvance.partialValue
                newEnd = newAdvance.partialValue
            }
            self.oldOffset = oldOffset
            self.newOffset = newOffset
            self.blocks = blocks
        }

        var oldCount: Int {
            blocks.reduce(0) { count, block in
                switch block {
                case .context: count + 1
                case .change(let removed, _): count + removed.count
                }
            }
        }

        var newCount: Int {
            blocks.reduce(0) { count, block in
                switch block {
                case .context: count + 1
                case .change(_, let added): count + added.count
                }
            }
        }

        var header: String {
            let oldStart = oldCount == 0 ? oldOffset : oldOffset + 1
            let newStart = newCount == 0 ? newOffset : newOffset + 1
            return "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        }

        var unifiedRows: [UnifiedRow] {
            var rows: [UnifiedRow] = []
            var oldNumber = oldOffset
            var newNumber = newOffset
            for block in blocks {
                switch block {
                case .context(let text):
                    oldNumber += 1
                    newNumber += 1
                    rows.append(.context(old: Line(number: oldNumber, text: text),
                                         new: Line(number: newNumber, text: text)))
                case .change(let removed, let added):
                    for text in removed {
                        oldNumber += 1
                        rows.append(.removed(Line(number: oldNumber, text: text)))
                    }
                    for text in added {
                        newNumber += 1
                        rows.append(.added(Line(number: newNumber, text: text)))
                    }
                }
            }
            return rows
        }

        var splitRows: [SplitRow] {
            var rows: [SplitRow] = []
            var oldNumber = oldOffset
            var newNumber = newOffset
            for block in blocks {
                switch block {
                case .context(let text):
                    oldNumber += 1
                    newNumber += 1
                    rows.append(.context(old: Line(number: oldNumber, text: text),
                                         new: Line(number: newNumber, text: text)))
                case .change(let removed, let added):
                    for index in 0..<max(removed.count, added.count) {
                        if index < removed.count, index < added.count {
                            oldNumber += 1
                            newNumber += 1
                            rows.append(.replacement(old: Line(number: oldNumber, text: removed[index]),
                                                     new: Line(number: newNumber, text: added[index])))
                        } else if index < removed.count {
                            oldNumber += 1
                            rows.append(.removed(Line(number: oldNumber, text: removed[index])))
                        } else {
                            newNumber += 1
                            rows.append(.added(Line(number: newNumber, text: added[index])))
                        }
                    }
                }
            }
            return rows
        }

        private enum CodingKeys: String, CodingKey { case oldOffset, newOffset, blocks }
    }

    enum ValidationError {
        case emptyIdentity, emptyPath, negativeOffset, emptyHunk, emptyChange
        case multilineText, lineNumberOverflow, inconsistentSide, overlappingHunks
        case inconsistentHunkGaps
    }

    private enum CodingKeys: String, CodingKey { case id, change, content }
}

extension DiffFile: Identifiable {}
extension DiffFile: Hashable {}
extension DiffFile: Sendable {}
extension DiffFile: Encodable {}

extension DiffFile: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let change = try container.decode(Change.self, forKey: .change)
        let content = try container.decode(Content.self, forKey: .content)
        do {
            try self.init(id: id, change: change, content: content)
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                debugDescription: "Invalid diff file: \(error)", underlyingError: error))
        }
    }
}

extension DiffFile.Change: Hashable {}
extension DiffFile.Change: Codable {}
extension DiffFile.Change: Sendable {}
extension DiffFile.Content: Hashable {}
extension DiffFile.Content: Codable {}
extension DiffFile.Content: Sendable {}
extension DiffFile.Block: Hashable {}
extension DiffFile.Block: Codable {}
extension DiffFile.Block: Sendable {}
extension DiffFile.Line: Hashable {}
extension DiffFile.Line: Codable {}
extension DiffFile.Line: Sendable {}
extension DiffFile.UnifiedRow: Hashable {}
extension DiffFile.UnifiedRow: Codable {}
extension DiffFile.UnifiedRow: Sendable {}
extension DiffFile.SplitRow: Hashable {}
extension DiffFile.SplitRow: Codable {}
extension DiffFile.SplitRow: Sendable {}
extension DiffFile.Hunk: Hashable {}
extension DiffFile.Hunk: Sendable {}
extension DiffFile.Hunk: Encodable {}

extension DiffFile.Hunk: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let oldOffset = try container.decode(Int.self, forKey: .oldOffset)
        let newOffset = try container.decode(Int.self, forKey: .newOffset)
        let blocks = try container.decode([DiffFile.Block].self, forKey: .blocks)
        do {
            try self.init(oldOffset: oldOffset, newOffset: newOffset, blocks: blocks)
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                debugDescription: "Invalid diff hunk: \(error)", underlyingError: error))
        }
    }
}

extension DiffFile.ValidationError: Error {}
extension DiffFile.ValidationError: Equatable {}
