# Shelved SwiftTUI ANSI-256 contribution draft

**Shelved on 2026-10-05; not queued for publication.** The user chose to document
the SSH capability findings and continue Chio library work. The reported SSH
sessions lack `COLORTERM`; this conversion patch does not restore that metadata.
See [the investigation's disposition](../Docs/Plan.md#proposed-ansi-256-conversion-correction).

Retained as historical local preparation; no upstream PR has been published. The accompanying
[patch](SwiftTUI-ansi256-upstream.patch) targets SwiftTUI
`7221dcec0a63de4ffa19f35a53cdd609a82f42a1`. It is separate from the
[Chio-pin patch](SwiftTUI-ansi256-quantization.patch); neither changes Chio's
normal dependency. The native gate was not completed, and no further contribution
work is planned.

## Proposed title

Correct ANSI-256 cube levels and include the grayscale ramp

## Proposed PR body

Dark custom surfaces become much lighter in ANSI-256 output because conversion
rounds onto a uniform six-level cube and never considers grayscale. For example,
`#211D2A` becomes index 59 (`#5F5F5F`). This change selects index 235 (`#262626`)
from the conventional extended palette.

Compare the nearest actual cube entry with the nearest grayscale entry using
squared distance between encoded RGB channels, with lower-index ties. The
implementation uses bounded arithmetic without a palette scan. Preserve the
nine existing named-color mappings, including `.white` → 255, as compatibility
exceptions. Capability detection, ANSI16 conversion, true-color output, alpha
composition and RGB-profile handling are unchanged. Customized terminal palettes
remain outside this approximation; this is not perceptual or contrast matching.

Add seven regression tests for compatibility mappings, all 240 extended-palette
entries, thresholds/ties, a 4,096-color independent oracle, gamut clamping,
foreground/background/underline output, and backdrop composition. Document the
conversion contract in the runtime architecture guide. Refresh ten ANSI-256
fixtures against this upstream revision; all other 55 capability fixtures are
byte-identical, and changed files differ only in indexed SGR numbers.

Validation on macOS with Swift 6.4:

- The seven proposed native tests and 13 native fixture cases pass in an isolated
  consumer using the exact native test sources, views and serializer. The fixture
  helper's explicit record/verify mode is selected in the consumer only.
- The six standalone source/test-ownership policy checks, fixture-matrix check,
  Swift formatting lint and patch whitespace check pass.
- Earlier integration against Chio's older native pin passed Chio terminal-host
  emission tests and a release dashboard PTY workflow. Separate captures verified
  ANSI-256 index 235, unchanged true-color RGB and no color under `NO_COLOR`, with
  clean exit and terminal-mode restoration. This is supporting evidence against
  the older pin, not current-main Chio integration or live Blink/SSH verification.

The required native `bun run test` gate has **not** run: `swiftly` and `bun` are
unavailable on this host, and the linked external `DEVELOPMENT.md` returns 404.
Consumer checks do not substitute for the native gate. Native CI, Linux and the
other supported-platform gates remain unverified for this patch.

## Disposition

The patch and draft preserve the investigation; neither is a shipping change or
an active task. Reopening would require a new dependency/publication decision,
the upstream repository's full gate and Chio integration verification. The
unrelated table-paint proposal remains separate.
