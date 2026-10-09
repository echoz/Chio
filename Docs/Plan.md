<a id="chio-plan-and-verification"></a>

# Chio plan

This document tracks active work, next steps and open questions. Current contracts
live in [Design](Design.md) and its decision index; implementation and showcase
checks live in [Verification](Verification.md). Completed release scope and results
live in [0.1.0](Releases/0.1.0.md).

## Proposed next slice: 2D maps

**Status:** Rendering spike implemented; reusable component remains proposed. The requested
outcome is one themed, flat 2D component supporting world and street vectors,
with detail reduction and a measured minimum usable size. The
[geographic map decision](Decisions/GeographicMaps.md) owns the detailed design,
research, dependencies and acceptance gates.

| Step | Deliverable | Completion criterion |
| --- | --- | --- |
| 1. Rendering proof | Local world and real neighborhood vectors rendered through SwiftTUI | Both recognizable; measured minimum sizes, useful reduced detail, three-theme legibility and performance budgets |
| 2. Reusable offline map | Shared camera, pan/zoom, markers, routes, labels and compact fallback | Model/raster/hosted coverage, authoritative bindings, resizing and stale-work rejection |
| 3. Verify and publish | Runnable example and matching showcase | Required macOS/Linux and release terminal checks, scoped SSH evidence, recordings/previews and published verification |

The runnable proof is `chio-map-spike`, under `Spikes/MapRendering`; it adds no
public library API. [Findings](Decisions/GeographicMaps.md#rendering-spike-findings)
record native rendering, source budgets, provisional sizes and verification.
The experiment now defaults to the accepted minimal geography and has an internal adapter
boundary carrying source credits and explicit coverage. Adjust silhouette,
minimal, abstract and source detail with `[` / `]`, or cycle with `d`. The lower
levels now explore actual land/water shape simplification as well as feature and
label selection. A checked drawing allowance rejects excessive work before
painting and keeps controls available for recovery. A second real source-schema
proof now adapts an offline OpenFreeMap vector tile into the same checked geometry
as the existing Overpass extract, sharing detail controls and native drawing.
The next work is the reusable offline component, including annotations,
cancellation and camera binding behavior. Do not promote the
experimental types unchanged: camera bindings, asynchronous preparation/stale
results, markers, routes and selection have not yet been implemented.

Runtime acquisition remains deferred. The second adapter reads a pinned local
MVT response; live vector tiles remain a later, separate decision. Its narrow
internal decoder adds no package dependency and does not establish static-musl
compatibility. Project policy still defers live external-service examples. See the
[tile-loading proposal](Decisions/GeographicMaps.md#later-proposal-vector-tile-loading).

## Remaining scope audit

The map proposal is the next design under consideration; there is no
committed broader component queue. Real application use remains useful validation.
Further hardening and a stable release are possible directions, not approved
numbered phases or completion promises.

Prioritize demonstrated regressions in shipped behavior: focus, selection,
editing, narrow layout, presentation, responsiveness and supported-platform
execution. Resolve defects at their owning layer. Changing the SwiftTUI pin or
shipping a fork requires a reproducible dependency decision and native/Chio
integration evidence; an ignored local patch is not a distribution strategy.

Public additions require a concrete consumer need and reusable UX value:

- Promote the diff prototype only after resolving source wrapping, large-input
  behavior and split-width policy with real usage evidence.
- Extract a general list/detail layout only if another consumer establishes a
  shared contract.
- Completion/history, async choices, wizards, broader file selection, tree
  adapters, status queues and more themes remain possible gaps, not tasks.
- Keep monitoring, clocks, workflow engines, annotation content, persistence, external
  services and repository operations with applications.

Prove an accepted addition in a small runnable example, document actual public
APIs, retain relevant model/raster/hosted regressions, and run a release terminal
workflow. Visible changes also follow the [showcase workflow](Verification.md#demo-site).

## Moved references

Earlier deep links remain here; follow the owning document for current details.

- <a id="current-release"></a><a id="component-coverage"></a>[0.1.0 release and delivered coverage](Releases/0.1.0.md#component-coverage)
- <a id="running-checks"></a><a id="demo-site"></a><a id="linux-and-ci"></a>[Current verification and showcase requirements](Verification.md)
- <a id="release-verification"></a><a id="platform-verification"></a><a id="showcase-verification"></a><a id="responsiveness-baseline"></a><a id="verified-on-macos"></a>[0.1.0 verification evidence](Releases/0.1.0.md#release-verification)
- <a id="macos-toolchain-findings"></a><a id="static-linux-blocker"></a>[Dependencies, toolchains and static Linux](Decisions/Dependencies.md)
- <a id="remaining-boundaries"></a>[Native integration boundaries](Decisions/NativeIntegration.md)
- <a id="btop-inspired-ui-inventory"></a>[Instrumentation decision and btop inventory](Decisions/Instrumentation.md#btop-inspired-ui-inventory)
- <a id="gh-dash-and-hunk-ui-inventory"></a>[Review composition and reference inventory](Decisions/ReviewInbox.md#gh-dash-and-hunk-ui-inventory)
- <a id="proposed-connected-table-grid-correction"></a>[Unapplied table-grid proposal](Decisions/TableRendering.md)
- <a id="proposed-ansi-256-conversion-correction"></a>[Shelved color-conversion investigation](Decisions/TerminalColors.md)
- <a id="markdown-syntax-highlighting"></a>[Markdown highlighting decision](Decisions/Markdown.md#markdown-syntax-highlighting)
- <a id="1-prove-the-terminal-rendering"></a><a id="2-build-the-reusable-offline-component"></a><a id="3-verify-and-publish-the-first-slice"></a><a id="later-proposal-vector-tile-loading"></a><a id="evidence-and-dependency-decisions"></a>[Detailed map proposal and delivery gates](Decisions/GeographicMaps.md)
