# Working on Disk Assessment

This is a local, read-only macOS storage assessment app. Read `README.md` for setup, commands and measurement limits. Keep changes focused on the user's request and follow the surrounding code style; do not reformat unrelated files.

## Architecture

- `src/App.swift`: SwiftUI app/window, native menus, lifecycle and headless scan entry point.
- `src/AssessmentModel.swift`: scan lifecycle, cancellation, private report cache, native dialogs/actions and report navigation state.
- `src/ReportViews.swift`: native SwiftUI report views and map/table explorer. Keep native controls accessible and responsive to window width.
- `src/ReportModel.swift`: pure native report indexing, navigation/rebasing, treemap layout and formatting.
- `src/SnapshotRefresh.swift`: in-place subtree refreshes, aggregate updates and partial-scan metadata. Preserve unscanned siblings and original scan age; do not imply that a folder refresh is a fresh whole-disk scan.
- `src/Scanner.swift`: native scanner and Codable snapshot models.
- `src/FinderActions.swift`: validates Finder targets against the loaded report and the current filesystem.
- `resources/web/index.html`, `resources/web/style.css`, `resources/web/app.js`: optional browser report, not bundled in the native app. No bundler, external assets or runtime packages.
- `resources/web/treemap.js`, `resources/web/ui-model.js`: pure layout and navigation helpers, also loaded by Node tests.
- `resources/cleanup-rules.json`: exact-path classification shared by the native and Python scanners.
- `tools/scan.py`, `tools/serve.py`, `tools/inspect_docker.py`: optional CLI/browser workflow using the Python standard library.

## Boundaries to preserve

- Scan filenames and metadata only. Do not read file contents, follow symlinks, cross filesystem devices, delete user data or add automatic cleanup.
- Do not start a whole-disk scan as part of development or testing. Use temporary fixtures. Preserve the user's saved report and any running scan.
- Report allocated blocks separately from logical file size. Candidate footprints are review leads, never guaranteed reclaimable bytes. Keep APFS sharing and coverage limitations visible.
- Keep native and Python classification consistent. Change shared exact-path rules in `resources/cleanup-rules.json`; check both implementations when changing suffix rules or snapshot contracts.
- Balanced map weights affect areas only. Labels, percentages, sorting, totals and exports use actual measured bytes.
- Treat filenames and report data as untrusted text. Use SwiftUI Text in the app and textContent/DOM construction in the browser report. Finder actions must accept only existing paths from the loaded report, open folders or reveal files, and never launch files or app bundles.
- Keep browser serving on loopback with an explicit asset allowlist. Keep app resources local, without telemetry or external scripts/fonts.
- Reports contain personal paths. Never commit or publish real reports, screenshots containing private paths, logs, credentials or generated app bundles. Use synthetic fixtures in tests; put local exports in ignored `reports/` or `snapshots/` directories.

## Validation and delivery

- `make lint`: dependency-free syntax/configuration and changed-line whitespace checks. This is not a full style or semantic linter; Swift type checking happens during the build.
- `make test`: native scanner/Finder/report/lifecycle fixtures, Python/release unit tests and JavaScript model/layout tests. It does not need a built app, write to GitHub or open Finder.
- `make check`: source checks, app build, signature verification and all tests. Run it for build/tooling, scanner, native model or cross-language changes.
- Add focused regression coverage for meaningful behavior changes. Do not add tests that merely mirror CSS or trivial reversible edits.
- For UI changes, rebuild and visually check the actual app in the affected layout and appearance. Keep small text at least 12 px, allow controls to wrap, and preserve light/dark and reduced-motion support. Do not change macOS preferences just to test appearance.
- Build output is `dist/Disk Assessment.app`; sources are copied into the bundle during `make build`. Editing source files does not update an already-running app. Reopen the rebuilt app when verifying it, without interrupting an active scan.
- Use `DISK_ASSESSMENT_REPORT_PATH` and a separate QA bundle identifier for synthetic UI checks. `--import-snapshot` previews a report without saving it to the cache.
- Builds stage/sign/verify before swapping bundles; preserve the previous bundle when a build fails. Signing uses `CODE_SIGN_IDENTITY`, then ignored `.signing-identity`, then ad hoc. Never silently downgrade a configured signing failure.
- `make dmg` creates a styled read-only image/checksum using build-only Python tools. `make release` pushes a version tag and uploads a draft release; do not run it without release authorization. Its `--dry-run` is read-only.
- Distinguish automated checks from manual GUI verification in the handoff. Local signing and DMG packaging do not establish notarized distribution support.

## Repository hygiene

Use `agent/` as the default prefix for new task branches. Do not discard unrelated user changes, rewrite history, add a remote or publish the repository unless requested. Keep runtime dependencies at zero unless a concrete feature needs one. Prefer the existing build scripts over introducing a second build system.
