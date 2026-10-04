# asciinema player

Unmodified release assets from [asciinema-player v3.17.0](https://github.com/asciinema/asciinema-player/releases/tag/v3.17.0).
Copyright Marcin Kulik and contributors. Distributed under the included
[Apache License 2.0](LICENSE); Chio's MIT license does not replace this license.

SHA-256 values match the upstream release asset digests:

```text
f619fe17597043564f03b2c6918b3daf890ee8b912fb408542fba11afade4fdb  asciinema-player.css
a13c37632e1b5c49fe9128417b9319a9b5bc64cb457dd5ae52cbba8a3aceb880  asciinema-player.min.js
```

The JavaScript release bundles its WebAssembly terminal emulator. No CDN or
package install is needed to build or play Chio's demo page.

Chio uses a screenshot and explicit playback instead of the player's NPT poster
option. In this release, an initial seek after an NPT poster can clear the
terminal while retaining advanced replay indices, leaving only later changes
visible. Keep backward-seek verification when changing the player version.
