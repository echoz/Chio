# Contextual keyboard help

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Share authored shortcut descriptions across compact hints and contextual help without registering input.

## Contextual keyboard help

Immutable `ShortcutHint` values contain authored key/action/detail text;
`ShortcutGroup` preserves title, order and duplicates. Both are Codable, Hashable
and Sendable. Empty details/groups are omitted; all-empty help has an explicit
message. Descriptions neither register actions nor parse key labels into input.
The pinned command registry and `KeyBinding` are not public.

`KeyHint`/`KeyHints` share those values with grouped, wrapping `KeyboardHelp`.
Applications derive descriptions from context/availability; native handlers remain
execution authority. Help is passive content for inline or native presentation.
A full-screen help reader retains the background subtree for native focus
restoration. Cover-wide handlers reach both controls and viewport; handlers inside
sheet content cannot reach its outer header/viewport.

Printable help shortcuts are scoped outside editors. A retained help context
survives modal focus changes; a context-independent reference avoids pending-focus
ambiguity. Pending presentation blocks background actions and consumes immediate
Escape, including input arriving before the next frame.

## Implementation and verification

- [KeyboardHelp.swift](../../Sources/Chio/Presentation/KeyboardHelp.swift)
- [KeyboardHelpRenderTests.swift](../../Tests/ChioTests/Presentation/KeyboardHelpRenderTests.swift)
