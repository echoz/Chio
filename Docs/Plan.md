<a id="chio-plan-and-verification"></a>

# Chio plan

This document tracks active work, next steps and open questions. Current contracts
live in [Design](Design.md) and its decision index; implementation and showcase
checks live in [Verification](Verification.md). Completed release scope and results
live in [0.1.0](Releases/0.1.0.md).

## Latest slice: online maps

**Status:** Accepted implementation with explicit offline and online world/street modes.
Provider comparisons remain shelved.

The explicit loader and opt-in online example are implemented. Current contracts
live in [online tile acquisition](Decisions/OnlineMaps.md), with rendering owned by
[geographic maps](Decisions/GeographicMaps.md). Offline launches remain the default.

The source choice is explicit: bundled data or online tiles. Online world views
use the same pipeline as regions and streets, starting at source zoom 1; there is
no automatic bundled-world fallback. Initial loading has no geographic source;
subsequent loads retain the last online snapshot. Native focus, complete coverage
and existing geometry/rendering budgets remain in force. Bundled copies of online
tiles can later supply the same tile pipeline;
disk caches and tile archives are not part of this correction.

Required verification for this slice:

- Verify checked values, acquisition lifecycle and exact marker fixtures, plus
  required macOS/Linux CI. CI uses deterministic local data.
- Run a separate bounded live-provider probe and adjacent-tile inspection.
  These establish integration, not provider availability or universal coverage.
- Capture the verified release recording, theme previews and showcase checks;
  deploy and inspect the published result before declaring the slice complete.

Disk caches, tile packs, credentials, arbitrary schemas, routing/geocoding and
provider parity remain outside this slice. Existing polygon cut-edge limitations
remain explicit. Keep revision-specific results in release records rather than
expanding this active plan with completed implementation history.

## Remaining scope audit

An isolated [Braille map visual experiment](../Spikes/BrailleMaps/README.md)
compares the existing renderer with outlines and sparse textures over identical
prepared geometry. Native raster captures record cell-colour collisions and halo
tradeoffs. It is awaiting visual direction, not promoted into the public map;
Pitwall integration is separate.

There is no committed broader component queue. Real application use of the
public map remains useful validation.
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
