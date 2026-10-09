# File selection

**Status:** Accepted; shipped in 0.1.0. These contracts remain current.

Add reusable directory browsing and checked confirmation of one file without promising confinement or reserving the file.

## File selection

`FilePicker` chooses one existing readable regular file through native searchable
selection plus directory loading/navigation, eligibility, errors/retry and explicit
confirmation. Browsing/filtering/cancel preserve the committed URL. Confirmation
commits only after checks; rejected binding writes keep the picker open with
feedback. Confirm/cancel makes the picker inactive; dismiss/recreate for another choice.

The start directory is not confinement. Inputs are absolute local file URLs;
dot components normalize lexically and Parent stops at `/`. File/directory
symlinks are followed outside the starting directory; display/returned paths retain
the chosen symlink route. Broken links, unreadable/special files cannot confirm.
Directories sort first, then case-insensitive names with deterministic ties.
Dot/filesystem-hidden entries require opt-in visibility.

`FileExtensionFilter.all` allows regular files; `.only([])` allows none;
`.only([""])` includes extensionless files. Matching uses the chosen filename's
extension case-insensitively without a leading dot. Authored sets are not trimmed
or repaired; directories stay navigable. Search is current-folder-only. Changed
start-directory/hidden policy reloads; theme/geometry preserve folder/filter.

An internal actor owns Foundation metadata/enumeration off the main actor, retained
through native state. Native `.task(id:)` cancels work. Every load/confirmation has
a fresh generation; completion checks cancellation before reading the captured
state binding and rejects stale generations. Navigation, confirmation-time editing,
cancel/disappearance invalidate work. Blocking calls may finish after cancellation,
but cannot commit cancelled results.

Confirmation rechecks current kind/readability without opening/reading contents,
reserving an inode or guaranteeing a later application open. The example reads
local listings without modifying files. Plain snapshots cannot await loading and
are rejected rather than pretending to contain a loaded listing.

## Implementation and verification

- [FilePicker.swift](../../Sources/Chio/Presentation/FilePicker.swift)
- [FilePickerTests.swift](../../Tests/ChioTests/Presentation/FilePickerTests.swift)
