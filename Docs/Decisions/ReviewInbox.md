# Dense review inbox composition

**Status:** Accepted example scope; shipped in 0.1.0. No public component API.

Validate dense review composition using existing primitives and local fixtures.

## Dense review inbox

The executable composes native Pickers, `SearchableList`, passive Markdown preview
and full-screen reading over sixteen fixed local review snapshots. Application
queue membership/sorting precede substring filtering; stable IDs preserve selection
through sorting. Queue changes immediately exclude invalid selection; activation
rechecks current membership before opening. Empty matches cannot preview/activate.

One mounted list retains its modifier chain while the optional sibling preview
appears at 88 × 26 or larger. The queue takes roughly two fifths of pane width with
a 40-column minimum; a two-cell gap separates preview. Without preview the queue
fills width. Preview is passive; full reading works at every size, and resize does
not dismiss it. Covers and pending presentation consume background queue actions;
ordinary printable input remains search text.

Opening first requests results focus, then native `onChange` presents after the
background frame commits focus. Escape cancels either phase; the callback reads
current phase to avoid reopening. This depends on pinned focus-before-lifecycle
ordering, without timers/yields or another focus system. A selected snapshot
composes the original `ReviewItem` and parsed document until the ID changes.
Fixtures remain Codable; derived snapshots follow the Markdown exception. No public
inbox, sorter, master/detail or review coordinator is implied.

## gh-dash and Hunk UI inventory

The delivered inbox exercises dense collections, sorting, preview visibility and
reader focus through existing primitives. The diff prototype adds immutable local
fixtures, aligned gutters, explicit summaries and logical hunk navigation.
Neither promises product parity. GitHub requests, Git/JJ/Sapling ingestion,
editor launching, note storage and agent sessions are application concerns.
The original [reference audit](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#gh-dash-and-hunk-ui-inventory)
remains historical design evidence, not a build order.

## Implementation and verification

- [InboxExampleView.swift](../../Examples/AgentDashboard/Presentation/InboxExampleView.swift)
- [InboxExampleTests.swift](../../Tests/ChioDashboardTests/Presentation/InboxExampleTests.swift)
