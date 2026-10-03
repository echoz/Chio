# Chio project guidance

Read [Docs/Design.md](Docs/Design.md) for accepted architecture and interaction
contracts, and [Docs/Plan.md](Docs/Plan.md) for verification and remaining work.
Keep those owning documents current instead of duplicating their contents here.

## Project boundaries

- Chio means attractive or pretty in Singlish; it is not an acronym. Preserve
  the tagline "Beautiful terminal interfaces for Swift."
- Build an opinionated, declarative design and interaction layer over SwiftTUI.
  SwiftTUI owns rendering, lifecycle, layout, state, focus, input, and scrolling.
  Prefer native control styles and composition; new components must add reusable UX.
- Keep one package and one public `Chio` library until real dependency boundaries
  justify more products. The first slice is the local simulated agent dashboard;
  forms, Markdown, and external integrations remain deferred.
- Apply themes through the environment. Keep behavior in component options and
  application layout in SwiftTUI composition. Do not use private upstream APIs to
  conceal styling or focus limitations.
- Validate theme and input changes with public raster and hosted-session APIs.
  Native focus, stable selection, and search text are distinct contracts. Keep
  batched-input regressions when modifying the transition into search.

Global engineering, organization, and worker-routing policies belong in
`~/.codex/AGENTS.md` and its companion instructions, not in this file.
