# Validation

## 0.4.0 — 2026-10-24

Checked on the local Apple Silicon Mac:

- `make check`: source checks, optimized native app build, strict signature verification and all fixture-based tests passed.
- Native report regression tests cover allowlists, threshold remainders, history rebasing after subtree replacement, map area accounting, balanced visibility, bounds and non-overlap.
- Native lifecycle tests use an isolated temporary report cache and filesystem fixtures. They cover saved-report loading, cancellation, navigation locking during scans, successful partial refreshes, retained sibling measurements/original scan age, private report writes, failed scans and stale refresh targets.
- Seven release test methods exercise fake Git/GitHub/build tools: clean branch/repository/tag guards, read-only dry runs, failed checks, source or remote movement during a build, corrupt checksums, successful draft asset upload, matching annotated tag reuse and upload failure recovery. These tests do not contact or write to GitHub.
- Existing native scanner/Finder/refresh, Python and browser model/layout tests passed.
- `make dmg` produced the versioned arm64 disk image and SHA-256 sidecar. Disk-image verification and SHA-256 validation passed. Read-only mounting confirmed the current executable, strict app signature, Applications shortcut, generated background and Finder layout. The app resources contain only its icon, license and classification rules; no reports, browser assets or Python dependencies are bundled.

Manual GUI checks used separately identified QA bundles and a synthetic `/Example Disk` report. They covered the welcome/last-report flow, overview, map selection and inspector, Return/back navigation, native table, review selection totals, large-files table and scan details. Light and dark appearances were checked within the app, without changing macOS preferences. The final map uses the vivid native blue/pink/orange palette. The DMG was also opened in Finder to verify its background, icon placement and drag-to-Applications instructions, then ejected.

No whole-disk scan was started and the user's saved report was not used for UI checks or overwritten. The signature tested here is ad hoc. Certificate signing, Gatekeeper acceptance on another Mac, notarization, Intel execution and a real GitHub release upload have not been validated.
