<a id="chio-plan-and-verification"></a>

# Chio plan

This document tracks active work, next steps and open questions. Current contracts
live in [Design](Design.md) and its decision index; implementation and showcase
checks live in [Verification](Verification.md). Completed release scope and results
live in [0.1.0](Releases/0.1.0.md).

## Latest slice: public offline maps

**Status:** Public component implemented; no longer an experimental target.
The adapter proof is accepted. Provider comparison refinements are shelved at the
user's direction; they do not block the reusable offline component.

The public `MapView` composes checked source geometry, an application-owned camera
and marker selection, markers, route overlays, shared detail and theme values.
Preparation runs on a serial worker with cancellation and stale-result rejection;
SwiftTUI owns actual allocation, focus, input, drawing and terminal lifecycle.
`chio-maps` in `Examples/Maps` consumes the same public API as downstream apps.
[Geographic maps](Decisions/GeographicMaps.md) owns its contracts and limitations.

Required verification:

- Checked public values/codecs and adapter errors; bounded geometry and overlays.
- Model, raster and hosted tests for cancellation, authoritative bindings,
  selection, native focus, resizing, themes and compact/overload recovery.
- Release example, PTY workflow, current recordings/previews and published QA.
- Required macOS/Linux CI on the integrated revision, with independent review.

Runtime acquisition remains deferred. The OpenFreeMap adapter decodes a pinned
local MVT response; it does not stitch or fetch neighboring tiles. Do not expand
this slice into provider parity, caching, routing services or a general GIS engine.

## Remaining scope audit

There is no committed broader component queue. Real application use of the
public offline map remains useful validation.
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
