# Chio design

Chio is an opinionated, declarative presentation and interaction layer over
SwiftTUI: “Beautiful terminal interfaces for Swift.” This document owns current
cross-cutting architecture and indexes the detailed decisions.

[Plan](Plan.md) owns active work and open questions; [Verification](Verification.md)
owns current checks; [Usage](Usage.md) and [Examples](Examples.md) own public recipes
and launch workflows. [Release records](Releases/0.1.0.md) preserve dated evidence.

## Ownership

SwiftTUI owns rendering, terminal lifecycle, layout, state, input, focus,
scrolling, scheduling and native presentation. Chio supplies semantic themes,
native control styles and composed views. One SwiftPM package exports the `Chio`
library and `chio-dashboard` executable; applications compose SwiftTUI directly.

A public addition must provide reusable presentation or interaction: readability,
focus/selection feedback, filtering, editing or navigation. Renaming a primitive
or making an example model immutable does not justify a library component.
Applications own clocks, monitoring, sorting policy, validation rules, review
state, persistence and external operations. Extract shared UI behavior only when
composition demonstrates a concrete missing contract. Showcase applications
validate the framework; their domain models do not define its product scope.
Coverage inventories describe gaps, without committing to catalog parity.

## Value contracts

Owned domain values and view configuration have `let` stored properties and pure
computed observations. Transformations return replacements and leave inputs
unchanged; local scratch mutation is permitted. Explicit mutable boundaries are
SwiftTUI state/binding/focus/namespace/environment wrappers, ArgumentParser command
options, filesystem resource owners, and live test-session recorders with frames,
continuations and deadlines.

Prefer synthesized `Hashable`, `Codable` and `Sendable` where their contracts fit.
Enforce restricted-value invariants through construction, replacement and decoding;
malformed decoding must reject through the same validation as construction.
Validation flags cannot replace invariants or contextual runtime checks. Draft
bindings read current retained storage before replacing a field, preserving other
fields even when multiple input events arrive before a frame.

Field descriptions and shortcut details are nonoptional strings: empty means no
supporting row. Shortcut decoding accepts historical missing/null detail as empty;
encoding always includes a string, and missing/empty details compare equally.
Errors retain meaningful optional presence: a present empty error still suppresses
help. Selection and native state ownership retain meaningful absence. Omitted
replacement arguments preserve values; supplied empty values clear them. Markdown
normalizes missing language/destination text at parsing. Search callbacks have
neutral defaults; modifier copies retain callbacks and native state identity.

Native `StrokeStyle` is only `Equatable` and `Sendable`, including inaccessible
state. `ChioTheme` and `Treatments` retain those conformances; `Colors`,
`SyntaxColors` and `Spacing` also support hashing and coding. Do not clone strokes
or add lossy coding to gain conformance. Parsed Markdown and report/presentation
snapshots are immutable, hashable and sendable without a persistence schema:
native table alignment is not Codable, and reconstructing a report from its agent
would lose the captured document. Process-relative example timekeeping likewise
has no persistence representation.

Incomplete agent drafts are valid editable values; checked creation enforces form
rules. Running progress is a checked finite fraction in `0..<1`; completion is a
separate phase. Simulation takes its step explicitly and returns replacement agents.

## Investigation outcome

| Reference | Native foundation | Chio contribution |
| --- | --- | --- |
| Lip Gloss / Charmtone | Layout, borders, colors, environment | Semantic palette and coherent defaults |
| Bubbles | Lists, tables, editing, scrolling, progress, palettes | Search composition, empty states and contextual help |
| Huh | Bindings, controls, submission, focus | Field presentation and validation visibility |
| Glamour | Rich text and links | Parsed Markdown composed into themed native views |
| btop | Canvas, groups, progress and authored layout | Compact styles and passive history presentation |
| gh-dash / Hunk | Lists, previews and ID-based scroll reveal | Example inbox composition and bounded diff proof |

Charm supplies visual references, not a Go API port or ANSI-string/layout engine.
Huh's Charm palette and Bubbles' hierarchy/help inform the default appearance.
btop informs compact instrumentation; gh-dash and Hunk inform review composition.
GitHub/VCS operations, authentication, file watching and agent protocols remain
application work. These examples do not establish product parity.

## Source ownership

| Path | Responsibility |
| --- | --- |
| `Sources/Chio/Domain` | Theme/shortcut values, pure search/membership, pagination, validation visibility, file observations and parsed Markdown |
| `Sources/Chio/Execution` | Filesystem loading/confirmation checks |
| `Sources/Chio/Presentation` | Components/environment integration; `Styles` owns native styles |
| `Examples/AgentDashboard` | Local models, workflows/views and thin entry point |
| `Tests/ChioTests`, `Tests/ChioDashboardTests` | Library responsibilities and example domain/hosted interactions |
| `Docs/Site`, `Docs/Media`, `Scripts/docs` | Static showcase, shared terminal assets and assembly without Swift build |

Create only useful responsibility groups; independently useful production types
have matching files and dedicated conformance extensions. Private nested helpers
retain inline conformances when extraction would widen access; raw enums keep
language-required placement. Shared frame recorders live in target `TestSupport`;
scenario fixtures/expectations remain beside suites. Global engineering/layout
rules remain in the working agreements rather than being duplicated here.

## Decision index

Read the relevant topic before changing its behavior. Accepted records remain
current authority after delivery; proposed and shelved records do not describe
shipped APIs. Each record keeps its scope, contracts, tradeoffs and useful evidence.
Update the owning record when a decision changes, marking superseded decisions
and linking their replacement. Keep execution status in Plan and release results
in Releases; avoid duplicating full contracts across documents.

| Topic | Status and responsibility |
| --- | --- |
| <a id="theme"></a>[Themes and native control styling](Decisions/Themes.md) | Accepted |
| <a id="compact-instrumentation"></a><a id="duration-presentation-and-example-owned-timekeeping"></a>[Compact instrumentation and duration display](Decisions/Instrumentation.md) | Accepted |
| <a id="searchable-selection"></a><a id="searchable-multiple-choice"></a>[Searchable selection and membership](Decisions/SearchableSelection.md) | Accepted |
| <a id="composition-and-layout"></a>[Responsive composition and status](Decisions/Composition.md) | Accepted |
| <a id="contextual-keyboard-help"></a>[Contextual keyboard help](Decisions/KeyboardHelp.md) | Accepted |
| <a id="tabs"></a>[Native tabs](Decisions/Tabs.md) | Accepted |
| <a id="pagination"></a>[Finite pagination](Decisions/Pagination.md) | Accepted |
| <a id="scrolling"></a>[Native scrolling](Decisions/Scrolling.md) | Accepted |
| <a id="expandable-groups-and-trees"></a>[Expandable groups and trees](Decisions/DisclosureGroups.md) | Accepted |
| <a id="command-palette"></a>[Native command palette](Decisions/CommandPalette.md) | Accepted |
| <a id="forms-and-agent-creation"></a><a id="password-and-multiline-input"></a>[Forms and native editing](Decisions/Forms.md) | Accepted |
| <a id="confirmation-and-transient-feedback"></a>[Confirmation and transient feedback](Decisions/Feedback.md) | Accepted |
| <a id="file-selection"></a>[File selection](Decisions/FileSelection.md) | Accepted |
| <a id="dense-review-inbox"></a>[Dense review inbox composition](Decisions/ReviewInbox.md) | Accepted example scope |
| <a id="read-only-diff-prototype"></a>[Read-only diff prototype](Decisions/DiffReader.md) | Accepted example scope |
| <a id="markdown-and-agent-reports"></a>[Markdown, code and interactive links](Decisions/Markdown.md) | Accepted |
| <a id="references-and-boundaries"></a>[Dependencies and distribution](Decisions/Dependencies.md) | Current pins, toolchain findings and static Linux blocker |
| [Native integration](Decisions/NativeIntegration.md) | Current limitations and ownership |
| [Terminal colors](Decisions/TerminalColors.md) | Accepted native detection; conversion experiment shelved |
| [Table rendering](Decisions/TableRendering.md) | Proposed correction; patches unapplied |
| <a id="geographic-maps-proposed"></a>[Geographic maps](Decisions/GeographicMaps.md) | Proposed; no implementation |

Topic anchors above retain earlier deep links. Historical implementation details
and original investigations remain in [the v0.1.0 documents](https://github.com/echoz/Chio/tree/v0.1.0/Docs)
and Git history.
