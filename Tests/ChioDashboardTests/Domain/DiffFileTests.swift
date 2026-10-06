@testable import ChioDashboard
import Foundation
import Testing

struct DiffFileTests {
    @Test("Uneven replacements derive independent old and new gutters")
    func unevenRows() throws {
        let hunk = try DiffFile.Hunk(oldOffset: 9, newOffset: 19, blocks: [
            .context("before"),
            .change(removed: ["old one", "old two"], added: ["new one"]),
            .context("after"),
            .change(removed: [], added: ["tail one", "tail two"]),
        ])
        let original = hunk

        #expect(hunk.oldCount == 4)
        #expect(hunk.newCount == 5)
        #expect(hunk.header == "@@ -10,4 +20,5 @@")
        #expect(hunk.unifiedRows == [
            .context(old: line(10, "before"), new: line(20, "before")),
            .removed(line(11, "old one")), .removed(line(12, "old two")),
            .added(line(21, "new one")),
            .context(old: line(13, "after"), new: line(22, "after")),
            .added(line(23, "tail one")), .added(line(24, "tail two")),
        ])
        #expect(hunk.splitRows == [
            .context(old: line(10, "before"), new: line(20, "before")),
            .replacement(old: line(11, "old one"), new: line(21, "new one")),
            .removed(line(12, "old two")),
            .context(old: line(13, "after"), new: line(22, "after")),
            .added(line(23, "tail one")),
            .added(line(24, "tail two")),
        ])
        #expect(hunk == original)
    }

    @Test("Insertion and deletion headers retain zero-count source offsets")
    func zeroCountHeaders() throws {
        let insertion = try DiffFile.Hunk(oldOffset: 0, newOffset: 0,
            blocks: [.change(removed: [], added: ["first", "second"])])
        let deletion = try DiffFile.Hunk(oldOffset: 4, newOffset: 4,
            blocks: [.change(removed: ["last"], added: [])])
        #expect(insertion.header == "@@ -0,0 +1,2 @@")
        #expect(insertion.unifiedRows == [.added(line(1, "first")), .added(line(2, "second"))])
        #expect(deletion.header == "@@ -5,1 +4,0 @@")
        #expect(deletion.splitRows == [.removed(line(5, "last"))])
    }

    @Test("Blank source lines remain present while uneven cells are absent")
    func blankLines() throws {
        let hunk = try DiffFile.Hunk(oldOffset: 0, newOffset: 0, blocks: [
            .context(""), .change(removed: ["", "removed"], added: [""]),
        ])
        #expect(hunk.splitRows == [
            .context(old: line(1, ""), new: line(1, "")),
            .replacement(old: line(2, ""), new: line(2, "")),
            .removed(line(3, "removed")),
        ])
    }

    @Test("Empty text files and binary summaries retain explicit file changes")
    func emptyAndBinaryFiles() throws {
        for change in [DiffFile.Change.added(path: "empty.txt"), .deleted(path: "empty.txt")] {
            let file = try DiffFile(id: "empty", change: change, content: .text([]))
            #expect(file.change == change)
            #expect(file.content == .text([]))
            #expect(file.hunks.isEmpty)
            #expect(file.addedLineCount == 0)
            #expect(file.removedLineCount == 0)
        }
        let binary = try DiffFile(id: "image", change: .modified(path: "image.png"), content: .binary)
        #expect(binary.hunks.isEmpty)
        #expect(binary.addedLineCount == 0)
        #expect(binary.removedLineCount == 0)
        #expect(binary.content != .text([]))
        let rename = try DiffFile(id: "rename", change: .renamed(from: "before.swift", to: "after.swift"),
                                  content: .text([]))
        #expect(rename.path == "after.swift")
    }

    @Test("Ordered hunks allow gaps and derive changed-line counts without context")
    func orderedHunks() throws {
        let first = try DiffFile.Hunk(oldOffset: 0, newOffset: 0, blocks: [
            .context("same"), .change(removed: ["one", "two"], added: ["new"]),
        ])
        let second = try DiffFile.Hunk(oldOffset: 8, newOffset: 7,
            blocks: [.change(removed: [], added: ["extra"]), .context("end")])
        let file = try DiffFile(id: "source", change: .modified(path: "source.swift"),
                                content: .text([first, second]))
        #expect(file.hunks == [first, second])
        #expect(file.addedLineCount == 2)
        #expect(file.removedLineCount == 2)
        #expect(second.header == "@@ -9,1 +8,2 @@")
        #expect(second.splitRows == [
            .added(line(8, "extra")),
            .context(old: line(9, "end"), new: line(9, "end")),
        ])
    }

    @Test("Source text preserves Unicode scalars, whitespace, tabs and long lines")
    func literalText() throws {
        let texts = ["\t  café  ", "e\u{301} 👩🏽‍💻 中文", String(repeating: "界", count: 300)]
        let hunk = try DiffFile.Hunk(oldOffset: 0, newOffset: 0,
            blocks: [.change(removed: [], added: texts)])
        let actual = hunk.unifiedRows.compactMap { row -> String? in
            if case .added(let line) = row { return line.text }
            return nil
        }
        #expect(actual.map { Array($0.utf8) } == texts.map { Array($0.utf8) })
        #expect(hunk.newCount == 3)
    }

    @Test("Hunk construction and decoding reject each malformed relationship")
    func invalidHunks() throws {
        let cases: [(HunkPayload, DiffFile.ValidationError)] = [
            (.init(oldOffset: -1, newOffset: 0, blocks: [.context("x")]), .negativeOffset),
            (.init(oldOffset: 0, newOffset: -1, blocks: [.context("x")]), .negativeOffset),
            (.init(oldOffset: 0, newOffset: 0, blocks: []), .emptyHunk),
            (.init(oldOffset: 0, newOffset: 0, blocks: [.change(removed: [], added: [])]), .emptyChange),
            (.init(oldOffset: 0, newOffset: 0, blocks: [.context("one\ntwo")]), .multilineText),
            (.init(oldOffset: 0, newOffset: 0, blocks: [.change(removed: ["one\rtwo"], added: [])]), .multilineText),
            (.init(oldOffset: 0, newOffset: 0, blocks: [.change(removed: [], added: ["one\u{2028}two"])]), .multilineText),
            (.init(oldOffset: Int.max, newOffset: 0, blocks: [.context("x")]), .lineNumberOverflow),
            (.init(oldOffset: 0, newOffset: Int.max, blocks: [.change(removed: [], added: ["x"])]), .lineNumberOverflow),
        ]
        for (payload, error) in cases {
            #expect(throws: error) {
                try DiffFile.Hunk(oldOffset: payload.oldOffset, newOffset: payload.newOffset, blocks: payload.blocks)
            }
            let data = try JSONEncoder().encode(payload)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(DiffFile.Hunk.self, from: data) }
        }
    }

    @Test("The largest representable source line remains valid without overflow")
    func lineNumberBoundary() throws {
        let hunk = try DiffFile.Hunk(oldOffset: Int.max - 1, newOffset: Int.max - 1,
                                     blocks: [.context("last")])
        #expect(hunk.unifiedRows == [.context(old: line(Int.max, "last"), new: line(Int.max, "last"))])
        #expect(hunk.header == "@@ -\(Int.max),1 +\(Int.max),1 @@")
    }

    @Test("Decoding an enclosing file cannot bypass hunk validation")
    func invalidEnclosedHunk() throws {
        let data = Data(#"{"id":"invalid","change":{"modified":{"path":"x"}},"content":{"text":{"_0":[{"oldOffset":-1,"newOffset":0,"blocks":[{"context":{"_0":"x"}}]}]}}}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DiffFile.self, from: data) }
    }

    @Test("File construction and decoding reject invalid metadata, sides and spans")
    func invalidFiles() throws {
        let context = try DiffFile.Hunk(oldOffset: 0, newOffset: 0, blocks: [.context("x")])
        let later = try DiffFile.Hunk(oldOffset: 3, newOffset: 3, blocks: [.context("y")])
        let oldOverlap = try DiffFile.Hunk(oldOffset: 0, newOffset: 2, blocks: [.context("z")])
        let newOverlap = try DiffFile.Hunk(oldOffset: 2, newOffset: 0, blocks: [.context("z")])
        let wrongAddedOffset = try DiffFile.Hunk(oldOffset: 1, newOffset: 0,
            blocks: [.change(removed: [], added: ["x"])])
        let wrongDeletedOffset = try DiffFile.Hunk(oldOffset: 0, newOffset: 1,
            blocks: [.change(removed: ["x"], added: [])])
        let unequalPrefix = try DiffFile.Hunk(oldOffset: 0, newOffset: 1, blocks: [.context("z")])
        let unequalGap = try DiffFile.Hunk(oldOffset: 2, newOffset: 3, blocks: [.context("z")])
        let skippedAddition = try DiffFile.Hunk(oldOffset: 0, newOffset: 1,
            blocks: [.change(removed: [], added: ["x"])])
        let skippedDeletion = try DiffFile.Hunk(oldOffset: 1, newOffset: 0,
            blocks: [.change(removed: ["x"], added: [])])
        let cases: [(FilePayload, DiffFile.ValidationError)] = [
            (.init(id: "", change: .modified(path: "x"), content: .text([])), .emptyIdentity),
            (.init(id: "x", change: .modified(path: ""), content: .text([])), .emptyPath),
            (.init(id: "x", change: .added(path: ""), content: .binary), .emptyPath),
            (.init(id: "x", change: .deleted(path: ""), content: .binary), .emptyPath),
            (.init(id: "x", change: .renamed(from: "", to: "x"), content: .text([])), .emptyPath),
            (.init(id: "x", change: .renamed(from: "x", to: ""), content: .text([])), .emptyPath),
            (.init(id: "x", change: .added(path: "x"), content: .text([context])), .inconsistentSide),
            (.init(id: "x", change: .deleted(path: "x"), content: .text([context])), .inconsistentSide),
            (.init(id: "x", change: .added(path: "x"), content: .text([wrongAddedOffset])), .inconsistentSide),
            (.init(id: "x", change: .deleted(path: "x"), content: .text([wrongDeletedOffset])), .inconsistentSide),
            (.init(id: "x", change: .modified(path: "x"), content: .text([later, context])), .overlappingHunks),
            (.init(id: "x", change: .modified(path: "x"), content: .text([context, oldOverlap])), .overlappingHunks),
            (.init(id: "x", change: .modified(path: "x"), content: .text([context, newOverlap])), .overlappingHunks),
            (.init(id: "x", change: .modified(path: "x"), content: .text([unequalPrefix])), .inconsistentHunkGaps),
            (.init(id: "x", change: .modified(path: "x"), content: .text([context, unequalGap])), .inconsistentHunkGaps),
            (.init(id: "x", change: .renamed(from: "x", to: "y"), content: .text([context, unequalGap])), .inconsistentHunkGaps),
            (.init(id: "x", change: .added(path: "x"), content: .text([skippedAddition])), .inconsistentHunkGaps),
            (.init(id: "x", change: .deleted(path: "x"), content: .text([skippedDeletion])), .inconsistentHunkGaps),
        ]
        for (payload, error) in cases {
            #expect(throws: error) { try DiffFile(id: payload.id, change: payload.change, content: payload.content) }
            let data = try JSONEncoder().encode(payload)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(DiffFile.self, from: data) }
        }
    }

    @Test("Validated values round-trip all alternatives and preserve derived rows")
    func codecs() throws {
        let insertion = try DiffFile.Hunk(oldOffset: 0, newOffset: 0,
            blocks: [.change(removed: [], added: ["", "new"])])
        let deletion = try DiffFile.Hunk(oldOffset: 0, newOffset: 0,
            blocks: [.change(removed: ["old"], added: [])])
        let mixed = try DiffFile.Hunk(oldOffset: 2, newOffset: 2,
            blocks: [.context("same"), .change(removed: ["before"], added: ["after", "extra"])])
        let files = try [
            DiffFile(id: "add", change: .added(path: "new"), content: .text([insertion])),
            DiffFile(id: "delete", change: .deleted(path: "old"), content: .text([deletion])),
            DiffFile(id: "modify", change: .modified(path: "same"), content: .text([mixed])),
            DiffFile(id: "rename", change: .renamed(from: "before", to: "after"), content: .text([])),
            DiffFile(id: "binary", change: .modified(path: "image"), content: .binary),
        ]
        let decoded = try JSONDecoder().decode([DiffFile].self, from: JSONEncoder().encode(files))
        #expect(decoded == files)
        #expect(Set(decoded) == Set(files))
        #expect(decoded[2].hunks[0].unifiedRows == mixed.unifiedRows)
        #expect(decoded[2].hunks[0].splitRows == mixed.splitRows)
    }

    private func line(_ number: Int, _ text: String) -> DiffFile.Line {
        DiffFile.Line(number: number, text: text)
    }

    private struct HunkPayload: Encodable {
        let oldOffset: Int
        let newOffset: Int
        let blocks: [DiffFile.Block]
    }

    private struct FilePayload: Encodable {
        let id: String
        let change: DiffFile.Change
        let content: DiffFile.Content
    }
}
