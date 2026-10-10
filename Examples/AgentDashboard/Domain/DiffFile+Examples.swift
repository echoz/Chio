extension DiffFile {
    /// Fixed normalized inputs, deliberately small enough for eager native layout.
    static let examples: [Self] = {
        do {
            return [
                try DiffFile(id: "greeting", change: .modified(path: "Sources/Greeting.swift"), content: .text([
                    try Hunk(oldOffset: 0, newOffset: 0, blocks: [
                        .context("struct Greeting {"),
                        .context("    let name: String"),
                        .context(""),
                        .change(removed: ["    var title: String {", "        \"Hello, \\(name)\"", "    }"],
                                added: ["    var title: String {", "        \"Hello, \\(name)!\"", "    }", "",
                                        "    var subtitle: String {", "        \"Ready to build\"", "    }"]),
                        .context("}"),
                    ]),
                    try Hunk(oldOffset: 38, newOffset: 42, blocks: [
                        .context("func welcome(_ name: String) {"),
                        .change(removed: ["    print(\"Hello\")"],
                                added: ["    let text = Greeting(name: name)", "    print(text.title)"]),
                        .context("}"),
                    ]),
                    try Hunk(oldOffset: 78, newOffset: 83, blocks: [
                        .context("let names = [\"Kai\", \"Mei\"]"),
                        .change(removed: ["for name in names {", "    print(name)", "}"],
                                added: ["names.forEach(welcome)"]),
                        .context(""),
                        .context("// Ready for the next greeting."),
                    ]),
                ])),
                try DiffFile(id: "unicode", change: .modified(path: "Fixtures/Unicode.swift"), content: .text([
                    try Hunk(oldOffset: 8, newOffset: 8, blocks: [
                        .context("// Café · 界 · 🐚"),
                        .change(removed: ["let title = \"café\"", "let blank = \"\"", ""],
                                added: ["let title = \"cafe\u{301}\"", "let shell = \"🐚 chio 界\"", "",
                                        "\tlet tabbed = \"kept as source\""]),
                        .context("    let long = \"" + String(repeating: "source ", count: 18) + "END_OF_SOURCE\""),
                        .context("// Trailing spaces stay here.   "),
                    ]),
                ])),
                try DiffFile(id: "empty-added", change: .added(path: "Fixtures/empty.txt"), content: .text([])),
                try DiffFile(id: "empty-deleted", change: .deleted(path: "Fixtures/obsolete.txt"), content: .text([])),
                try DiffFile(id: "renamed", change: .renamed(from: "Docs/GettingStarted.md", to: "Docs/Guide.md"), content: .text([])),
                try DiffFile(id: "binary", change: .modified(path: "Assets/mark.png"), content: .binary),
            ]
        } catch {
            preconditionFailure("Invalid local diff fixture: \(error)")
        }
    }()
}
