# Working on Disk Assessment

This is a local, read-only macOS storage assessment app. Read `README.md` for setup, commands and measurement limits. Keep changes focused on the user's request and follow the surrounding code style; do not reformat unrelated files.

## Architecture

- `App.swift`: AppKit window, WKWebView bridge, scan lifecycle, private report cache, native menus and dialogs.
- `Scanner.swift`: native scanner and Codable snapshot models.
- `FinderActions.swift`: validates Finder targets against the loaded report and the current filesystem.
- `index.html`, `style.css`, `app.js`: bundled report and UI. No bundler, external assets or runtime packages.
- `treemap.js`, `ui-model.js`: pure layout and navigation helpers, also loaded by Node tests.
- `cleanup-rules.json`: exact-path classification shared by the native and Python scanners.
- `scan.py`, `serve.py`, `inspect_docker.py`: optional CLI/browser workflow using the Python standard library.

## Boundaries to preserve

- Scan filenames and metadata only. Do not read file contents, follow symlinks, cross filesystem devices, delete user data or add automatic cleanup.
- Do not start a whole-disk scan as part of development or testing. Use temporary fixtures. Preserve the user's saved report and any running scan.
- Report allocated blocks separately from logical file size. Candidate footprints are review leads, never guaranteed reclaimable bytes. Keep APFS sharing and coverage limitations visible.
- Keep native and Python classification consistent. Change shared exact-path rules in `cleanup-rules.json`; check both implementations when changing suffix rules or snapshot contracts.
- Balanced map weights affect areas only. Labels, percentages, sorting, totals and exports use actual measured bytes.
- Treat filenames and report data as untrusted text. Use textContent/DOM construction, and validate native bridge requests. Finder actions must accept only existing paths from the loaded report, open folders or reveal files, and never launch files or app bundles.
- Keep browser serving on loopback with an explicit asset allowlist. Keep app resources local, without telemetry or external scripts/fonts.
- Reports contain personal paths. Never commit or publish real reports, screenshots containing private paths, logs, credentials or generated app bundles. Use synthetic fixtures in tests; put local exports in ignored `reports/` or `snapshots/` directories.

## Validation and delivery

- `make lint`: dependency-free syntax/configuration and changed-line whitespace checks. This is not a full style or semantic linter; Swift type checking happens during the build.
- `make test`: native scanner/Finder fixtures, Python unit tests and JavaScript model/layout tests. It does not need a built app and does not open Finder.
- `make check`: source checks, app build, signature verification and all tests. Run it for build/tooling, scanner, bridge or cross-language changes.
- Add focused regression coverage for meaningful behavior changes. Do not add tests that merely mirror CSS or trivial reversible edits.
- For UI changes, rebuild and visually check the actual app in the affected layout and appearance. Keep small text at least 12 px, allow controls to wrap, and preserve light/dark and reduced-motion support. Do not change macOS preferences just to test appearance.
- Build output is `dist/Disk Assessment.app`; sources are copied into the bundle during `make build`. Editing source files does not update an already-running app. Reopen the rebuilt app when verifying it, without interrupting an active scan.
- Distinguish automated checks from manual GUI verification in the handoff. The local signature is ad hoc; do not claim notarized distribution support.

## Repository hygiene

Use `agent/` as the default prefix for new task branches. Do not discard unrelated user changes, rewrite history, add a remote or publish the repository unless requested. Keep runtime dependencies at zero unless a concrete feature needs one. Prefer the existing build scripts over introducing a second build system.
