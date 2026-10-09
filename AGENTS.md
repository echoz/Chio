# Chio project guidance

Read [Docs/Design.md](Docs/Design.md) for current architecture and its decision
index, then the relevant topic files in `Docs/Decisions/` before changing behavior.
Read [Docs/Plan.md](Docs/Plan.md) for active work and
[Docs/Verification.md](Docs/Verification.md) for applicable checks. Accepted
decisions remain authoritative after delivery; proposals and shelved work do not
change shipped contracts. `Docs/Releases/` holds revision-specific evidence.
Update each owning document instead of duplicating contracts or history here.

## Project boundaries

- Chio means attractive or pretty in Singlish; it is not an acronym. Preserve
  the tagline "Beautiful terminal interfaces for Swift."
- Build an opinionated, declarative design and interaction layer over SwiftTUI.
  SwiftTUI owns rendering, lifecycle, layout, state, focus, input, and scrolling.
  Prefer native control styles and composition; new components must add reusable UX.
- Use immutable stored properties for owned domain and view-configuration values.
  Follow the value contracts and explicit state-owner exceptions in
  [Design.md](Docs/Design.md#value-contracts).
- Keep one package and one public `Chio` library until real dependency boundaries
  justify more products. Examples default to local fixtures. Online map acquisition
  is an explicit opt-in; other external service integrations remain deferred.
- Apply themes through the environment. Keep behavior in component options and
  application layout in SwiftTUI composition. Do not use private upstream APIs to
  conceal styling or focus limitations.
- Validate theme and input changes with public raster and hosted-session APIs.
  Native focus, stable selection, and search text are distinct contracts. Keep
  batched-input regressions when modifying the transition into search.
- Keep form validation rules and draft ownership in the application. Chio owns
  field presentation and error visibility; native controls and focus perform editing.
- Parse Markdown when content changes, then compose native views from the immutable
  document. Keep parser types internal; native scroll views own document navigation.

Global engineering, organization, and worker-routing policies belong in
`~/.codex/AGENTS.md` and its companion instructions, not in this file.
