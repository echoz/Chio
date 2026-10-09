# Read-only diff prototype

**Status:** Accepted example scope; shipped in 0.1.0. No public component API.

Validate bounded diff presentation before considering a public component.

## Read-only diff prototype

Executable-only `DiffFile`/views provide a bounded proof, without public Chio API
or dependency. Immutable changes distinguish modified/added/deleted/renamed paths;
binary content differs from textual hunks, including empty textual files.

Zero-based hunk offsets and context/change blocks are checked on construction and
decoding: reject negative/overflowing ranges, multiline source entries, empty
changes, overlap and inconsistent unchanged gaps. Complete normalized file diffs
require equal omitted old/new prefixes/gaps; partial hunks need another contract.
Counts/numbers/unified/split rows derive from blocks. Missing split cells differ
from present empty source lines; replacement lines pair in order with excess
retained on their own side.

One native two-axis scroll owner aligns split panes. Literal native Text and public
cell measurement retain source; markers/ink distinguish changes independently of
success/error status. Below 92 columns presentation is unified; widening restores
requested layout. Native anchors reveal a retained logical hunk after navigation,
file changes/relayout. Manual scrolling does not change that explicit target;
theme preserves offset. Palette policy remains example-local.

Lines are unwrapped because native word wrapping can remove boundary whitespace
and add continuation marks. Wrapped source requires a faithful native contract.
Long lines widen split panes and require horizontal navigation. Tabs/Unicode use
native measurement, without editor tab-stop/terminal agreement guarantees. The
eager small-fixture reader is not virtualized or certified for large patches.
There is no diff parser, VCS adapter, repository/review/annotation subsystem.

## Implementation and verification

- [DiffFile.swift](../../Examples/AgentDashboard/Domain/DiffFile.swift)
- [DiffFileTests.swift](../../Tests/ChioDashboardTests/Domain/DiffFileTests.swift)
- [DiffExampleTests.swift](../../Tests/ChioDashboardTests/Presentation/DiffExampleTests.swift)
