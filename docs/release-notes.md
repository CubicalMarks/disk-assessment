# Disk Assessment 0.4.0

Disk Assessment now has a fully native SwiftUI interface: a sidebar, toolbar, vivid storage map, sortable tables, item inspector, candidate checklist and dedicated scan-details view. Native controls follow the Mac's appearance and wrap where needed.

The existing read-only scanner and saved-report format are preserved. Folder refreshes retain navigation, untouched siblings and the original scan date. Allocated blocks remain separate from logical size, and candidate footprints remain review leads rather than promised reclaimable space.

Builds now stage and verify a fresh app before swapping it into place. Configure an existing signing certificate with `CODE_SIGN_IDENTITY` or a Git-ignored `.signing-identity`; local builds otherwise use ad-hoc signing.

The drag-to-Applications DMG includes a styled Finder layout and SHA-256 checksum. `make release` validates a clean, pushed main branch, builds/tests/packages the version, and uploads a draft GitHub release. It never publishes the draft automatically. This local distribution workflow does not add notarization.
