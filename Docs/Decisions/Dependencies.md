# Dependencies and distribution

**Status:** Accepted dependency choices; static Linux remains blocked.

Keep dependency choices reproducible and distinguish supported execution from unverified static distribution.

## Dependency choices

The library uses published `SwiftTUIViews`; the executable uses `SwiftTUI` and tests
use public `SwiftTUIRuntime` raster/hosted APIs, without testing SPI or private APIs.
All four direct dependencies are revision-pinned:

| Dependency | Pin and reason |
| --- | --- |
| SwiftTUI | `2d84ac7083993da2ef52e9d3d30255467efb9553`; inspected evolving beta API |
| Swift Markdown 0.9.0 | `25cb61d3482054b09ae76ca4f281b1bfe7fe5a43`; revision permits conditional Windows unsafe flags |
| Tree-sitter 0.26.13 | `d97971e24500218865c05ed1febdee2acf41bae1`; last release with upstream SwiftPM manifest |
| tree-sitter-swift 0.7.4 | `82bb3a533e0801fd2bbaa11dc49676e10bf41948`; generated C grammar |

Version-based Chio requirements (`from:` or `exact:`) cannot resolve this
revision-pinned graph. Consumers of the experimental v0.1.0 source release pin
Chio's immutable revision `1bcc08ce23747c8c8b1121e3add3c37951f7b09e`.
Swift Markdown brings swift-cmark 0.9.0 built from source, without a separately
installed library. Tree-sitter/Swift grammar are MIT-licensed C targets requiring
neither a Swift wrapper nor grammar generation. The grammar copies unused queries;
Chio does no query-resource I/O and generates no Objective-C/Foundation accessor.
Build evidence is recorded in [0.1.0](../Releases/0.1.0.md); the current static Linux
blocker is below. Ordinary glibc support does not establish static-musl distribution.

## macOS toolchain findings

Some Apple Swift 6.4 toolchains do not discover the installed Swift Testing macro
plugin. `verify.sh` detects and supplies it when available; its command is the
preferred entry point. The attempted native backend could not find Testing.

Apple Swift `6.4.0.34.1` with Command Line Tools also emitted linker warnings for
nonexistent `CommandLineTools/Developer/usr/lib` and framework search paths.
An independent dependency-free package reproduced the warning and ran; Xcode 27
built that probe without it. This is recorded in
[SwiftPM issue #10557](https://github.com/swiftlang/swift-package-manager/issues/10557).
Chio adds no suppression flags and does not change the global developer selection.

## Static Linux blocker

Static Linux remains blocked. A Swift 6.4.0 ARM64 cross-build with the matching
`swift-6.4.0-RELEASE_static-linux-0.1.0` SDK failed because upstream SwiftFiglet's
platform imports omit Musl, leaving POSIX symbols such as `access`, `opendir`
and `fopen` unavailable. Figlet is reached through Chio's library dependency,
not only the example. No static executable was produced.

[Run 37174543215](https://github.com/echoz/Chio/actions/runs/37174543215)
reproduced the blocker on x86_64. The manual
[static workflow](../../.github/workflows/static-linux.yml) retains failures; if a
future build succeeds, it checks ELF dependencies and executes the terminal
workflow. Use the matching official open-source compiler/Static Linux SDK;
Apple's Xcode compiler is not a substitute.

Source inspection found additional Musl gaps in native math, terminal, image,
link, PTY and socket paths. These are audit findings, not later compiler
failures: compilation stopped at Figlet. Native termios code also contains
Darwin VMIN/VTIME tuple indices. Linux `cfmakeraw` supplies the tested path's
correct values, but passing restoration tests do not prove those indices portable.
One import fix alone cannot establish static support; a changed dependency needs
compiled, linked and executed evidence before a static-distribution claim.
