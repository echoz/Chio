# Themes and native control styling

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Use semantic themes and native styles to give controls coherent paint while retaining SwiftTUI behavior.

## Theme

`ChioTheme` contains semantic colors, syntax colors, spacing and treatments;
`.chioTheme(...)` applies it through the environment and installs native styles.
Use `replacing(...)` on the theme and nested values to customize presentation.
Construction and replacement preserve nonnegative spacing and printable
single-cell glyph preconditions. Options own component behavior; application
composition owns content and layout.

The default, light and btop presets share the same interaction policy. The
executable's `ExampleTheme` is an internal comparison choice, not a public theme
registry or restriction on custom values. Theme changes preserve query, stable
selection, focus, entered values and relevant native scroll positions.

Native groups, lists, tables, buttons, links, text fields/editors, pickers, toggles,
tabs, scroll/disclosure views, progress, spinners and prompts share semantic roles.
Bordered buttons inherit their surface and use an accent outline for focus/enabled
press, or error for destructive actions. Idle borders use the ordinary border
color; disabled controls retain native dimming. Focus-effect suppression removes
the focused outline. Authored labels remain native content. Outlines avoid a
whole-cell rectangular fill behind rounded border glyphs.

## Implementation and verification

- [ChioTheme.swift](../../Sources/Chio/Theme/Domain/ChioTheme.swift)
- [View+ChioTheme.swift](../../Sources/Chio/Theme/Presentation/View+ChioTheme.swift)
- [ChioThemeTests.swift](../../Tests/ChioTests/Theme/Domain/ChioThemeTests.swift)

## References

- [SwiftTUI style system](https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIViews/SwiftTUIViews.docc/Style-System.md)
- [SwiftTUI theme model](https://github.com/SwiftTUI/swift-tui/blob/2d84ac7083993da2ef52e9d3d30255467efb9553/Sources/SwiftTUIPrimitives/Styling/Theme.swift)
- [Huh themes](https://github.com/charmbracelet/huh/blob/main/theme.go)
- [Bubbles list](https://github.com/charmbracelet/bubbles/tree/main/list) and [help](https://github.com/charmbracelet/bubbles/tree/main/help)
