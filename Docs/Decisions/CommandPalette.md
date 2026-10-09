# Native command palette

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Style the native palette and keep application commands and presentation sequencing with the application.

## Command palette

`ChioPaletteStyle` styles native `paletteSheet`; apply the theme outside the
declaration. Applications register actions through native `Panel`, `keyCommand`
and `paletteCommand`, without a Chio registry or coordinator.

Fuzzy filtering preserves stable command IDs. The native editor keeps editing
focus while arrows/Tab move selection; Return activates natively and Escape
dismisses. Disabled commands remain visible/inert; unmatched queries show feedback.
A bounded window reveals selection; short terminals omit descriptions but retain
names/help. `initialQuery` seeds each opening. Resolved editor bindings prevent
reopening from activating earlier-lifetime state.

The dashboard queues an action until native presentation becomes false, allowing
focus restoration before launching a form/report. Replacing palette with cover in
the same frame would capture departing palette focus. Opening batches may precede
the first palette frame: a bounded adapter carries simple text/backspace and
Escape, consuming navigation/Return and blocking background shortcuts until native
focus arrives. This is not general event replay. Dropdown surface/divider remain
native chrome; pinned `sheetStyle` cannot style that container.

## Implementation and verification

- [ChioPaletteStyle.swift](../../Sources/Chio/Presentation/Styles/ChioPaletteStyle.swift)
- [ChioPaletteStyleTests.swift](../../Tests/ChioTests/Presentation/ChioPaletteStyleTests.swift)
