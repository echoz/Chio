# Finite pagination

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Provide checked finite paging values and native controls without taking ownership of data loading.

## Pagination

`Pagination` models finite nonnegative count, positive size and zero-based current
page, nil exactly when empty. Construction/replacement check preconditions;
malformed decoding throws. The value is Hashable, Codable and Sendable. Page counts
and ranges use constant-time arithmetic through `Int.max`, without page arrays.

`selectingPage(at:)` returns nil for invalid indices. First/previous/next/last
transitions clamp at boundaries. `updatingTotalCount(to:)` preserves a valid page
or clamps to the last; `resizingPages(to:)` retains the old first visible item in
the new page. Empty-to-nonempty starts at page one; explicit construction starts
a new result set. Applications own count/query changes and loading policy.

`PageControl` binds the complete value, composing native Previous/Next buttons and
page/item-range summaries. Empty/single-page actions are disabled. Arrows/Home/End
are scoped to buttons. Actions reread retained bindings; rejected/transformed
writes create no local optimistic cursor. Native focus, pointer input and layout
remain authoritative. Async paging, unknown totals and cross-page item selection
are outside this finite-value contract.

## Implementation and verification

- [Pagination.swift](../../Sources/Chio/Pagination/Domain/Pagination.swift)
- [PageControlTests.swift](../../Tests/ChioTests/Pagination/Presentation/PageControlTests.swift)
