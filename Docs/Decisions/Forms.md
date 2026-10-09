# Forms and native editing

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Compose native editors with field presentation and validation visibility; applications own drafts and rules.

## Forms and agent creation

`FormField` composes a heading, supplied native control and wrapping help/error.
Errors replace help and carry a visible marker. Picker/toggle labels stay
accessible while visually omitted inside fields to avoid duplicate headings.
`FormValidation<Field>` records exits/submission, not rules or cached results.
Applications supply current ordered issues: `message(for:in:)` hides errors until
blur/submission; `recordingExit(from:)` returns visibility; `submitting(_:)` returns
visibility and first invalid field for native focus. Apps exclude hidden fields.

Native controls/bindings/focus own editing. The compact picker maps arrows and
wheel/accessibility to selection without a pointer option menu; toggles retain
Space/Return. Ordinary composition is the form API; the pin has no `Form` declaration.
Keep persistent drafts above responsive layouts. Read current storage in binding
setters, validate current drafts before committing snapshots, and reveal the first
invalid heading/error with native scroll readers. Cancel restores accepted values
and visibility; restoration is not an exit from the abandoned field.

Agent creation uses a retained dashboard beneath a native full-screen cover,
scrolling fields with actions outside, and explicit initial Name focus. Names
must be nonblank and at most 32 characters; Test reveals a required suite of at
most 40. Hidden suite drafts remain retained but unvalidated. Creation trims outer
whitespace, adds one UUID-identified process-local agent, clears filtering and
selects it; Cancel adds nothing. Both submission and checked creation validate.
Duplicate submits are guarded by current presentation state.

During pre-frame cover handoff, dashboard shortcuts are blocked; simple name
text, initial Tab focus and submission are adapted narrowly. Invalid submission
reveals errors on arrival; valid submission creates once. The return transition
consumes stale events until the updated list renders. Native editing resumes with cover focus.
Forms/checklist/settings examples keep rules, save/cancel and drafts application-owned;
there is no form DSL, field registry, scheduler or persistence subsystem.

## Password and multiline input

Native `SecureField` uses `ChioTextFieldStyle`. SwiftTUI masks before styling and
withholds secure values/text-query metadata from public semantic snapshots.
Authored labels/help/feedback must never interpolate passwords. Mask/reveal
controls are not public options; Chio adds no credential model.

`ChioTextEditorStyle` places protected `editorContent` once with surface, inset,
border and focused accent. Native binding, cursor, selection, wrapping, paste,
viewport and one focus stop remain intact. Applications bound height. Tab leaves;
Return inserts a newline; Home/End navigate the logical line. Secure-field Return
uses native submission when supplied.

Enabled editor text samples the surrounding foreground before styling;
`.chioTheme` supplies both foreground and frame style. A standalone style cannot
retroactively change sampled text paint. Disabled text keeps native placeholder
paint/dimming without an extra opacity layer or replacement editing content.
The local example clears passwords on Save/Cancel and never authenticates,
transports or persists them.

## Implementation and verification

- [FormField.swift](../../Sources/Chio/Presentation/FormField.swift)
- [FormValidation.swift](../../Sources/Chio/Domain/FormValidation.swift)
- [FormValidationTests.swift](../../Tests/ChioTests/Domain/FormValidationTests.swift)
- [GroupedFormExampleTests.swift](../../Tests/ChioDashboardTests/Presentation/GroupedFormExampleTests.swift)
