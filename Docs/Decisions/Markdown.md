# Markdown, code and interactive links

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Parse documents once and compose semantic native views with source-faithful code and explicit link actions.

## Markdown and agent reports

`MarkdownDocument(source)` parses once into an immutable Hashable/Sendable value;
applications retain it until content changes. Third-party AST/parser types remain
internal. `MarkdownView` consumes the document/theme; apps supply vertical scrolling.
Native views compose headings, rich paragraphs, emphasis, code, lists/tasks,
quotes, rules and tables. Each paragraph is one rich Text with native span wrapping.
Smart punctuation is disabled. Quotes use a text marker because pinned leading-edge
borders disappear on one-row content. Images show alt/source; HTML stays literal.

Fenced code preserves parsed whitespace in a native horizontal scroll view.
Swift-only highlighting is automatic: first whitespace-delimited fence word,
case-insensitive `swift`. Tree-sitter parses during document construction and stores
private immutable semantic ranges beside authoritative text. Grapheme-aligned
source slices feed native rich Text without formatting/reconstruction. Unknown,
unlabeled, unsafe-range or oversized (>65,536 UTF-8 bytes) code stays wholly plain.
A deterministic 4,096-progress-checkpoint budget falls back to plain without clock
reads; scanner operations are outside callbacks, so this is not a wall-time/memory
bound. An iterative C cursor classifies roles; strings/interpolation share string
paint. Partial/malformed grammar recognition always retains literal source.

Equality/hash use code language/text with Swift canonical Unicode semantics;
derived ranges do not define identity or require bytewise-equal spellings.
`ChioTheme.syntax` supplies keyword/type/string/number/comment colors, independent
of status roles; ordinary foreground handles identifiers/punctuation/operators.
`.codeHighlighting(.plain)` suppresses paint; `.automatic` is default. Modifiers
retain installed link actions, native scroll identity and ranges. Syntax colors
are separate from the existing Codable `Colors` schema.

Whitespace means parsed Markdown text: cmark normalizes CRLF to LF; blank rows
and parsed trailing newline remain. Native tabs measure one cell and Unicode
width is approximate. Highlighting preserves those semantics, adding no renderer.

Tables retain cells/native alignments and compose native Table/TableRow, with
horizontal scrolling for readable narrow-screen columns. Body cells retain rich
styling; native headers accept uniform plain labels. Tables are eager, not large
data grids. `ChioTableStyle` supplies semantic headers/rounded borders, but native
chrome masks border/background paint. Public row backgrounds preserve Markdown
body contrast; no replacement table conceals the upstream limitation.

The existing initializer keeps links passive with readable destinations. Explicit
`MarkdownView(document, openLink: OpenLinkAction { ... })` opts into native links;
false never falls back to the system opener. Applications own schemes, relative
paths, fragments, external effects and feedback. Parsed `LinkDestination` is not
rewritten; Chio does not resolve/fetch/open it. Document identity preserves link
structure, distinct from text resembling passive fallback; no persisted schema exists.

Each link has one complete rich label/native focus stop; adjacent links stay
separate even with equal destinations. Empty destinations stay passive; empty labels
with destinations show them. Table body links activate; headers stay readable
plain labels/destinations. `ChioLinkStyle` accents/underlines enabled links, adds
bold/selected surface for focus/press, and dims disabled links whose native input
is inert. Suppression removes focus paint while retaining activation. Link paint
wins over inline code for visible focus, preserving authored strong/emphasis.
Native wrapping/hit regions, traversal and scroll reveal remain authoritative.

Reports capture current agent and parsed document once; underlying simulation does
not rewrite the reader. Reopening captures latest state. User-authored metadata is
escaped as literal Markdown; content identifies local simulation. Native covers
retain background query/selection/focus, focus the reader on arrival and restore
on close. Header/hints stay outside scrolling even at 36 × 18. Pending cover input
blocks background shortcuts so batched activation cannot accidentally quit.

## Markdown syntax highlighting

Swift highlighting uses pinned Tree-sitter 0.26.13 and tree-sitter-swift 0.7.4 C
targets, privately behind `MarkdownDocument`. They require no Swift wrapper,
JavaScript runtime or grammar generation. The grammar copies an unused query
bundle; Chio performs no query-resource I/O. The [contracts above](#markdown-and-agent-reports)
define source fidelity, budgets, plain fallback and theme behavior.

A prior SwiftSyntax 604.0.0 candidate crashed on deeply nested input despite
configured nesting limits, so it did not satisfy the plain-fallback contract.
The selected C integration passed macOS and glibc Linux checks. A local historical
probe measured roughly 1.40 ms versus 0.019 ms per document construction with
versus without classification, and about 4.56 MB additional unstripped executable
size. These are single-machine observations, not portable performance guarantees
or a clean-build comparison. The [dependency investigation](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#markdown-syntax-highlighting)
retains the full measurements and rejected alternatives. Static-musl support
remains blocked separately.

## Implementation and verification

- [MarkdownDocument.swift](../../Sources/Chio/Markdown/Domain/MarkdownDocument.swift)
- [MarkdownView.swift](../../Sources/Chio/Markdown/Presentation/MarkdownView.swift)
- [MarkdownCodeTests.swift](../../Tests/ChioTests/Markdown/Domain/MarkdownCodeTests.swift)
- [MarkdownLinkTests.swift](../../Tests/ChioTests/Markdown/Presentation/MarkdownLinkTests.swift)
