# Disk Assessment

A native SwiftUI macOS app for exploring disk usage, reviewing cleanup candidates and opening items in Finder. It is local and read-only, with no background scanner or menu-bar utility.

## Build and run

Requirements for development:

- macOS 13 or newer.
- Apple's Xcode command-line tools (`xcode-select --install` if missing).
- Python 3.10+ and Node.js 18+ for source checks and tests. Neither is needed to run the built app.

```sh
make check
open "dist/Disk Assessment.app"
```

The build targets the current Mac's architecture and uses SwiftUI and AppKit, with a native Swift scanner and treemap. There are no package downloads or runtime dependencies for building or running the app. You can also open the app in Finder or copy it to Applications. Builds stage and verify a fresh bundle before swapping it into `dist/`; the old bundle stays in `.build/app-stage.*` so a running app's files are preserved. Reopen the app to use a new build, after any active scan finishes.

Signing defaults to ad hoc for local use. To select an existing certificate, put its fingerprint on one line in `.signing-identity` (ignored by Git), or set `CODE_SIGN_IDENTITY` for a build. The environment variable takes precedence; `CODE_SIGN_IDENTITY=-` explicitly selects ad-hoc signing. A configured signing failure stops the build and preserves the previous bundle. Neither local signing option establishes notarized distribution support.

Choose **Scan Mac** or **Choose Folder…**, then browse the resulting map, review candidates or largest files. **View last report** reopens the last completed scan. Cancelling a scan preserves that report.

## Disk images and releases

`make dmg` builds/signs a fresh app and creates `dist/Disk-Assessment-<version>-<architecture>.dmg` plus a SHA-256 sidecar. The compressed, read-only image has a custom Finder layout: drag **Disk Assessment** onto **Applications**, then launch it from Applications and eject the image. Quit an existing instance before replacing it. Saved reports remain in Application Support.

Packaging uses macOS tools plus pinned, build-only `ds-store` and `mac-alias` Python libraries installed into ignored `.build/dmg-tools`. The first packaging run needs internet. These libraries write the Finder layout without Automation permissions; they are not bundled with the app. The DMG is not notarized or signed for public distribution, and downloaded copies may be blocked by Gatekeeper.

The release command follows the local Transcribe workflow. Install/authenticate GitHub CLI, set `CFBundleShortVersionString` to the desired `X.Y.Z` and increment `CFBundleVersion` in `resources/Info.plist`, then commit and push the intended sources to `main`:

```sh
bash scripts/release.sh --dry-run
make release
# Optional: make release RELEASE_ARGS="--prerelease --notes-file docs/release-notes.md"
```

The dry run checks repository access, branch state and version tags without building or writing remotely. `make release` requires clean `main` matching `origin/main`, runs checks/tests, packages and verifies the DMG, pushes `vX.Y.Z`, and uploads the DMG/checksum to a **draft** GitHub release. Review and publish the draft on GitHub. It never commits sources, pushes branch changes, retargets existing tags or overwrites release assets. After an upload failure, inspect Releases for a partial draft before retrying. Public Developer ID signing and notarization are separate work.

## Using the report

- The native sidebar opens **Overview**, **Storage Map**, **Review**, **Large Files** and **Scan Details**. The toolbar offers a new scan, export and folder selection; the File and Navigate menus provide keyboard shortcuts.
- Select an item to inspect its size and path; double-click a folder, or use **Explore Folder** in the inspector (Return), to explore it. Use Back, Forward, Up, breadcrumbs and the current-folder filter to navigate. The map/list selector switches to a native sortable table.
- **Balanced** scaling keeps smaller entries visible using square-root weights with a minimum of one third of an equal share per entry. **Actual size** uses areas proportional to allocated bytes. Labels, percentages, totals, sorting and exports always use measured bytes.
- **Open in Finder** opens a folder; **Show in Finder** selects a file. Right-click an item for native actions. Command-R reveals the selection. Finder targets must belong to the loaded report and still exist; files and app bundles are never launched.
- The reload icon beside the current-folder Finder button rescans that folder in place. Progress and Cancel stay inside the map/list area, without replacing the report or moving its scroll position. It keeps parent navigation, updates ancestor totals and review entries, and returns to the existing report on cancellation or failure. A successful refresh is saved with the report. Other folders retain their earlier measurements; directory/symlink/mount coverage counts still describe the original scan. The largest-files list contains the largest known entries after partial refreshes. A full scan rebuilds global rankings and reconciles hard links shared across refreshed and older folders.
- Review checkboxes collect paths for copying. They do not authorize cleanup. There are no deletion controls.
- **Export Snapshot…** saves a JSON report. **New Scan** returns to the scan choices. The UI follows the Mac's appearance and reduced-motion settings.

## Development

| Command | Purpose |
| --- | --- |
| `make build` | Build and sign the app, then verify its signature |
| `make dmg` | Build/sign and package a styled disk image with SHA-256 |
| `make release` | Check, build, tag and upload a draft GitHub release |
| `make run` | Build and open the app |
| `make lint` | Check shell, JavaScript, Swift and Python syntax, JSON/plist parsing and changed-line whitespace |
| `make test` | Run native, Python and JavaScript tests using temporary fixtures |
| `make check` | Run source checks, build/signature verification and tests |

The scripts also work directly: `bash scripts/lint.sh`, `bash scripts/build-app.sh` and `bash scripts/test-app.sh`. Tests do not require an existing app bundle, a real scan, Docker or a saved report. Source checks use the installed language tools; there is no third-party style linter or automatic reformatting. Swift compilation in the build checks types; syntax checks alone do not establish correct behavior. Native UI changes need a visual check in the rebuilt app; browser HTML/CSS changes need a separate browser check.

Tests cover allocated/sparse file accounting, hard-link deduplication, symlinks, access error reporting, cancellation, candidate overlap, snapshot compatibility, Finder target validation, native/browser navigation history, map proportions/bounds, native scan lifecycle/report preservation and release guards. Finder tests resolve temporary paths without opening items. Release tests use fake tools and never write to GitHub.

For isolated UI checks, set `DISK_ASSESSMENT_REPORT_PATH` to a synthetic report cache. `--import-snapshot /path/to/fixture.json` opens a report without saving it into the cache. `DISK_ASSESSMENT_APPEARANCE=light` or `dark` previews that appearance within the app; omit it to follow macOS. Keep QA preferences isolated with a separate bundle identifier. Never use real reports for committed screenshots.

Read [AGENTS.md](AGENTS.md) for implementation boundaries and change-specific validation. Editor whitespace settings are in `.editorconfig`. No remote or CI provider is assumed by the local checks.

### Source map

```text
src/              Swift application code
resources/web/    Optional browser report (not bundled with the native app)
resources/        Shared cleanup rules and app configuration
tests/            Swift, JavaScript and Python tests
scripts/          Build, source checks and test runners
tools/            Python utilities and icon generation
```

| File | Responsibility |
| --- | --- |
| `src/App.swift` | SwiftUI app/window, native menus, lifecycle and headless scan entry point |
| `src/AssessmentModel.swift` | Scan lifecycle, cancellation, private report cache, navigation state and native dialogs/actions |
| `src/ReportViews.swift` | Native overview, treemap/table explorer, inspector, review, large files and scan details |
| `src/ReportModel.swift` | Pure report indexing, navigation/rebasing, map layout and display formatting |
| `src/SnapshotRefresh.swift` | Validated subtree refreshes, parent accounting and refresh timestamps |
| `src/Scanner.swift` | Native metadata scanner and snapshot models |
| `src/FinderActions.swift` | Report allowlist and current file/folder validation |
| `resources/web/index.html`, `resources/web/style.css`, `resources/web/app.js` | Optional browser report interface |
| `resources/web/treemap.js`, `resources/web/ui-model.js` | Pure map layout and report navigation helpers |
| `resources/cleanup-rules.json` | Shared exact-path candidate classification |
| `tools/scan.py`, `tools/serve.py`, `tools/inspect_docker.py` | Optional Python/browser tools |
| `tools/Icon.swift`, `resources/Info.plist`, `scripts/build-app.sh` | App icon generation, bundle configuration and build/signing |
| `scripts/build-dmg.sh`, `scripts/layout-dmg.py`, `scripts/DMGBackground.swift` | Styled DMG packaging and Finder layout |
| `scripts/release.sh` | Guarded version tagging and draft GitHub release uploads |

## Measurement limits

The scanner reads filenames and filesystem metadata only. It skips symlinks and other filesystem devices, and sums regular-file `st_blocks × 512` rather than logical file length. Hard links count once, at their first encountered location. Parent totals include entries hidden by the display threshold.

APFS clones, compression, snapshots, directory metadata and inaccessible paths prevent an exact reconciliation with physical disk usage or recoverable space. Files can also change during a scan. Access failures remain visible; the app does not request administrator privileges or change Full Disk Access settings.

The volume bar distinguishes measured file blocks, usage not attributed by the scan, other shared usage and available space. Unattributed usage is the positive difference between volume-used bytes and measured file blocks. Other shared usage is the capacity remainder after data-volume used and available bytes; it includes sibling APFS volumes and overhead. Neither category means junk.

Candidate classification uses explicit rules in `resources/cleanup-rules.json` and the scanners' suffix rules. Candidates below 10 MiB are omitted. Parent candidates own nested candidates to avoid double-counting. “Rebuildable” is a review lead; it does not prove files are disposable. The app makes no duplicate-file or last-access-time claims.

For system-managed storage, use the owning tools: [Apple local snapshots](https://support.apple.com/en-ie/102154), [Docker disk images](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) and [Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).

## Privacy and local data

The app saves the last completed report to `~/Library/Application Support/Disk Assessment/last-report.json`, with private directory/file permissions. Reports contain personal paths. Keep exports in the ignored `reports/` or `snapshots/` directories; do not commit them. Build output, compiler caches, default CLI reports, local environment files and logs are also ignored. Renamed exports elsewhere still need care before staging.

No file contents are scanned, and there are no external assets, telemetry or network services in the app. Optional browser serving binds to loopback, exposes only allowed report assets and has no filesystem mutation endpoints or directory listing.

## Optional Python/browser workflow

The original browser report uses Python's standard library and plain HTML/CSS/JavaScript:

```sh
python3 tools/scan.py --root "$HOME"
python3 tools/serve.py
```

Open <http://127.0.0.1:8765>. Omitting `--root` scans `/System/Volumes/Data` on macOS. `--minimum-mib 10` retains more tree detail; the default is 50 MiB. **Reload snapshot** reloads the JSON and does not start a scan. Finder integration is available only in the native app.

The CLI writes `report-data.json` by default; use `--output reports/example.json` after creating `reports/` to save a named export. The native executable also supports a headless scan:

```sh
"dist/Disk Assessment.app/Contents/MacOS/DiskAssessment" \
  --scan /path/to/folder --output /tmp/report.json
```

For an optional Docker breakdown, run `python3 tools/inspect_docker.py` after creating the default CLI report. It invokes only `docker system df --format json` and appends the daemon's estimates. It performs no pruning. These estimates overlap the disk-image footprint and must not be added to candidate totals.

## License

[MIT License](LICENSE). Copyright (c) 2026 Marcus Libäck.
