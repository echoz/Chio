# SwiftTUI ANSI-256 contribution draft

Local preparation only; no upstream PR has been published. The accompanying
[patch](SwiftTUI-ansi256-upstream.patch) targets SwiftTUI
`7221dcec0a63de4ffa19f35a53cdd609a82f42a1`. It is separate from the
[Chio-pin patch](SwiftTUI-ansi256-quantization.patch); neither changes Chio's
normal dependency. Native gate completion and publication remain outstanding.

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

## Before publication

Apply the patch to the recorded SwiftTUI revision. Follow upstream's current
contribution instructions, obtain the missing development guide, install its
required tools, and run `bun run test`. Use its native fixture recording script
to confirm the retained outputs, with recording variables unset for the gate.
Review any new differences rather than accepting snapshot changes mechanically.

Choose upstream publication or a deliberately maintained pinned fork before
distributing the change. Once a reproducible dependency is selected, apply the
[Chio emission regression](Chio-ansi256-emission.patch) and run Chio's full
integration gate. Keep the unrelated table-paint proposal separate.
