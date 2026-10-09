# Responsive composition and status

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Keep responsive layouts and status presentation composable while preserving interaction state.

## Composition and layout

`KeyHint` renders one description, `KeyHints` wraps compact hints, and `StatusBar`
presents application status. Narrow layouts retain usable search/selection,
readable status, errors/actions and essential hints. Resize/theme changes preserve
interaction state. Keep state above alternative layouts: native `ViewThatFits`
resolves all alternatives.

The dashboard stacks below 88 columns and prioritizes list/essential hints below
26 rows. Its full layout targets 100 × 30 or larger; 36 × 18 is the compact target.
Local examples demonstrate successful/failed runs and empty results without
external services. Their fixture sizes do not establish large-data behavior.

## Implementation and verification

- [AgentDashboard](../../Examples/AgentDashboard)
- [ChioDashboardTests](../../Tests/ChioDashboardTests)
