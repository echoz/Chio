# Terminal color capabilities

**Status:** Accepted native detection policy; the conversion experiment is shelved.

Applications declare terminal capabilities; Chio retains authored palettes and delegates detection/conversion to SwiftTUI.

## Current behavior

SwiftTUI owns color-depth detection/conversion. The pin reads environment variables,
without true-color query/terminfo: missing `COLORTERM` selects ANSI256 for
`xterm-256color` and ANSI16 for `xterm-ghostty`, neither proving capability. Its
ANSI256 conversion poorly maps dark RGB; default surface maps to `#5F5F5F` instead
of `#211D2A`. True-color SSH sessions declare metadata as described in
[Examples.md](../Examples.md#colors-over-ssh). Applications own explicit capability
policy; Chio keeps authored palettes/native detection. The historical conversion
patch is shelved, absent from the pin, and does not fix discovery.

## Proposed ANSI-256 conversion correction

**Shelved.** The user closed this investigation on 2026-10-05: no SwiftTUI PR,
maintained fork, forced true-color default or Chio color-depth flag is planned.

Ghostty and Blink SSH reports lacked `COLORTERM`/`TERM_PROGRAM`; the pinned
detector selected ANSI16 for `xterm-ghostty` and ANSI256 for `xterm-256color`.
That missing remote metadata does not describe the terminal's actual RGB support.
The inspected SSH server accepted `LANG`/`LC_*`, not `COLORTERM`; no configuration
was changed. See [Colors over SSH](../Examples.md#colors-over-ssh) for explicit
launch/forwarding options. PTY evidence verifies authored RGB with
`COLORTERM=truecolor` and suppression under `NO_COLOR`, not the final live-device
appearance. `--force-color` alone does not select true color.

Separately, the pinned indexed-color quantizer rounds onto a uniform cube and
ignores the grayscale ramp, washing out dark colors. The
[native conversion](https://github.com/echoz/Chio/blob/v0.1.0/Patches/SwiftTUI-ansi256-quantization.patch),
[consumer regression](https://github.com/echoz/Chio/blob/v0.1.0/Patches/Chio-ansi256-emission.patch) and
[upstream preparation](https://github.com/echoz/Chio/blob/v0.1.0/Patches/SwiftTUI-ansi256-upstream.md)
are unapplied experiments archived in `v0.1.0`. Focused probes passed, but full
native gates did not run; no upstream PR was published. Detailed algorithms,
compatibility exceptions and evidence
remain in the [shelved investigation](https://github.com/echoz/Chio/blob/v0.1.0/Docs/Plan.md#proposed-ansi-256-conversion-correction).
Reopening it requires a new dependency decision, not another automatic roadmap task.
