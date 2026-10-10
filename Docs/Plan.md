<a id="chio-plan-and-verification"></a>

# Chio plan

This document tracks active work, next steps and open questions. Current contracts
live in [Design](Design.md) and its decision index; implementation and showcase
checks live in [Verification](Verification.md). Completed release scope and results
live in [0.1.0](Releases/0.1.0.md).

## Instrumentation presentation candidate

**Status:** Implemented candidate; review, merge and release pending. The pull
request records verification and showcase evidence.

Add reusable `MeasurementGauge` bars/dials and `InstrumentReadout` plain/segmented
styles, with the same optional style on `DurationText`. Applications retain scales,
units, sampling and timekeeping. Contracts live in
[instrumentation](Decisions/Instrumentation.md); the metrics and timer examples
exercise wide and compact composition. `Sparkline` already supplies passive history
presentation and is unchanged in this slice. Applications retain history
collection, retention and interpretation.

Required completion evidence: focused validation/rendering/accessibility and hosted
interaction checks, pinned engineering gate, macOS/Linux checks, and the affected
metrics/timer recordings plus three-theme previews from the verified release
binary. Prepare showcase assets in the PR; publish only after merge and verify the
live result before claiming showcase completion.

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

Disk caches, tile packs and routing/geocoding were excluded from that delivered
slice and are now approved follow-up scope below. Arbitrary schemas and provider
parity remain outside it. Existing polygon cut-edge limitations remain explicit.
Keep revision-specific results in release records rather than expanding this
active plan with completed implementation history.

## Approved map expansion

**Status:** Scope approved on 2026-10-09; implementation and public APIs pending.
The shipped map component remains as described in the existing decisions. The
following order is the proposed delivery sequence, with one testable slice at a time.

First close the two reproduced audit defects: overflow-safe keyboard-hint spacing,
and conservative polygon admission across all accepted rings. The latter must not
assume hole containment that construction and decoding do not establish. Preserve
existing valid-input behavior and add focused regressions before extending maps.

| Order | Capability | First useful outcome and acceptance evidence |
| --- | --- | --- |
| 1 | Persistent tile cache | Reuse acquired raw tiles across launches through the existing decode/preparation pipeline. Prove source isolation, bounded disk use, freshness rules, eviction, corrupt-entry handling and interrupted-write recovery. |
| 2 | Downloadable offline tile packs | Explicitly select an area and zoom range, inspect the planned tile/byte limits, download with progress/cancellation, then reopen the pack without network access. Preserve coverage, attribution and checksums; incomplete downloads must not appear complete. |
| 3 | Geocoding | Forward place/address search and reverse coordinate lookup through an explicit provider adapter. Return bounded results that applications can turn into markers and camera changes; prove no-result/failure distinctions, cancellation and stale-result rejection. |
| 4 | Routing | Explicit route requests between supplied locations through a provider adapter, returning checked geometry and available distance/duration metadata. Compose with existing route overlays; prove no-route/failure distinctions, cancellation, stale-result rejection and route work limits. |

### Boundaries and open choices

- Keep `MapView` free of network and disk effects. Add explicit, opt-in services
  beside acquisition; applications choose when to call them, where to store data,
  which providers to use and how to present results. SwiftTUI retains native state,
  focus, input and rendering ownership.
- Reuse one raw-tile acquisition/decoding path for online responses, persistent
  cache entries and packaged copies. A pack can supply bundled tiles through that
  path. Source selection remains explicit: no automatic switch to unrelated bundled
  geography. Cache freshness and intentional offline-pack retention are distinct
  policies; an evictable cache is not a completeness guarantee for a pack.
- Scope persisted identity to the source and tile scheme/address, retain provenance
  and attribution, and check imported bytes and metadata before use. A provider's
  revision string alone does not establish immutable bytes or an atomic snapshot.
  Choose pack format, schema/versioning and migration behavior during storage design;
  PMTiles/MBTiles support is not decided by approving downloadable packs.
- Choose the first geocoding and routing providers after evaluating their actual
  contracts, terms, attribution, rate limits and static-Linux dependency impact.
  Keep tile, geocoding and routing capabilities independently replaceable; changing
  a provider must not redefine visual detail. Provider credentials, when needed,
  are explicitly supplied by the application; no credential store is implied.
- Tile-pack acquisition needs a source that permits the planned downloads and
  explicit request/byte/concurrency limits. Approval of packs does not authorize
  bulk downloading from the current interactive endpoint. Offline tile packs do
  not imply an offline routing graph or offline geocoding database.
- Prove each service with deterministic fixtures and real adapter boundary tests,
  then macOS/Linux checks and a bounded live-provider probe where applicable.
  Extend `chio-maps` and its showcase for each visible slice. Service integration
  is in scope; implementing a routing engine, live navigation or a geocoder index
  is not implied by this roadmap.

## Remaining scope audit

The Braille map comparison is resolved: the existing fill toggle supplies outline
presentation, route clearance and dot markers are integrated, and the texture
experiment is removed. [Geographic maps](Decisions/GeographicMaps.md) owns the
resulting presentation contract. Pitwall integration remains separate.

The 2026-10-09 global-guidance audit found two tile-admission defects (path-budget
classification and wrong-typed names), plus incomplete exhaustive switches. The
focused corrections preserve native state ownership and valid public inputs.
Meaningful optional selections/loading states and raw/projected/source models
retain their distinct contracts; no broad consolidation was justified.

The follow-up applies exhaustive owned-enum policies, concrete constructors,
internal Boolean names and dedicated conformances across production and examples,
with affected tests updated alongside their owners. Public labels, persisted keys,
native state identity and rendering remain compatibility constraints.

Older untouched test fixtures can adopt constructor spelling when their behavior
is next changed; the [pinned local lint gate](Verification.md#shared-engineering-rules)
tracks their reviewed baseline and rejects new findings. They do not justify a
separate rewrite. Intentional single-case
filters, extensible upstream/raw-input switches, native wrappers and private
nested conformances retain their documented roles.

The approved map expansion above is the current feature queue. Real application
use of the public map remains useful validation. Other component additions and a
new stable release remain possible directions, not delivery promises.

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
- Keep monitoring, clocks, workflow engines, annotation content, general application
  persistence and repository operations with applications. Map storage and service
  adapters follow the explicit boundaries in the approved expansion above.

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
