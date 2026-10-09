# Connected table rendering

**Status:** Proposed correction; historical patches are unapplied and not shipped.

The current table behavior is documented with [Markdown tables](Markdown.md#markdown-and-agent-reports). A correction needs a reproducible dependency decision before distribution.

## Proposed connected table grid correction

Two historical patches are archived in `v0.1.0` and **not applied to the default build**:
[SwiftTUI table paints](https://github.com/echoz/Chio/blob/v0.1.0/Patches/SwiftTUI-table-style-paints.patch) against the
pinned native revision, and [Chio connected grid](https://github.com/echoz/Chio/blob/v0.1.0/Patches/Chio-connected-table-grid.patch)
against `b47280b`. The combined preview passed local Chio tests and terminal paint
checks, but full upstream gates and API-inventory regeneration were not run.
Shipping it needs an upstream fix or an explicit reproducible dependency decision
and fresh integration evidence. The
[original investigation](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#proposed-connected-table-grid-correction)
records the candidate and its limits; an ignored preview binary is not shipped.
