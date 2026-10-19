# Disk Assessment

A local, read-only macOS app for exploring disk usage, reviewing cleanup candidates and opening items in Finder. It runs in a normal window with no background scanner or menu-bar utility.

## Build and run

Requirements for development:

- macOS 13 or newer.
- Apple's Xcode command-line tools (`xcode-select --install` if missing).
- Python 3.10+ and Node.js 18+ for source checks and tests. Neither is needed to run the built app.

```sh
make check
open "dist/Disk Assessment.app"
```

The build targets the current Mac's architecture and bundles the report assets, native Swift scanner and macOS WebKit integration. There are no package downloads or runtime dependencies. You can also open the app in Finder or copy it to Applications. The app is signed ad hoc for local use; it is not notarized for distribution.

Choose **Scan Mac** or **Choose Folder…**, then browse the resulting map, review candidates or largest files. **View last report** reopens the last completed scan. Cancelling a scan preserves that report.

## Using the report

- Select an item to inspect its size and path; double-click a folder, or press Return on its map tile, to explore it. Use Back, Forward, Up, breadcrumbs and the current-folder filter to navigate.
- **Balanced** scaling keeps smaller entries visible using square-root weights with a minimum of one third of an equal share per entry. **Actual size** uses areas proportional to allocated bytes. Labels, percentages, totals, sorting and exports always use measured bytes.
- **Open in Finder** opens a folder; **Show in Finder** selects a file. Right-click or use **More…** for native actions. Command-R reveals the selection. Finder targets must belong to the loaded report and still exist; files and app bundles are never launched.
- Review checkboxes collect paths for copying. They do not authorize cleanup. There are no deletion controls.
- **Export Snapshot…** saves a JSON report. **New Scan** returns to the scan choices. The UI follows the Mac's appearance and reduced-motion settings.

## Development

| Command | Purpose |
| --- | --- |
| `make build` | Build and sign the app, then verify its signature |
| `make lint` | Check shell, JavaScript, Swift and Python syntax, JSON/plist parsing and changed-line whitespace |
| `make test` | Run native, Python and JavaScript tests using temporary fixtures |
| `make check` | Run source checks, build/signature verification and tests |

The scripts also work directly: `bash scripts/lint.sh`, `bash scripts/build-app.sh` and `bash scripts/test-app.sh`. Tests do not require an existing app bundle, a real scan, Docker or a saved report. Source checks use the installed language tools; there is no third-party style linter or automatic reformatting. Swift compilation in the build checks types; the syntax checks alone do not establish correct behavior. HTML/CSS changes need a visual check in the rebuilt app.

Tests cover allocated/sparse file accounting, hard-link deduplication, symlinks, access error reporting, cancellation, candidate overlap, snapshot compatibility, Finder target validation, navigation history, stable colors and map proportions/bounds. Finder tests resolve temporary paths without opening items.

Read [AGENTS.md](AGENTS.md) for implementation boundaries and change-specific validation. Editor whitespace settings are in `.editorconfig`. No remote or CI provider is assumed by the local checks.

### Source map

```text
src/              Swift application code
resources/web/    Bundled HTML, CSS and JavaScript
resources/        Shared cleanup rules and app configuration
tests/            Swift, JavaScript and Python tests
scripts/          Build, source checks and test runners
tools/            Python utilities and icon generation
```

| File | Responsibility |
| --- | --- |
| `src/App.swift` | AppKit window, WKWebView bridge, scan lifecycle, report persistence and native dialogs/menus |
| `src/Scanner.swift` | Native metadata scanner and snapshot models |
| `src/FinderActions.swift` | Report allowlist and current file/folder validation |
| `resources/web/index.html`, `resources/web/style.css`, `resources/web/app.js` | Shared report interface bundled into the app |
| `resources/web/treemap.js`, `resources/web/ui-model.js` | Pure map layout and report navigation helpers |
| `resources/cleanup-rules.json` | Shared exact-path candidate classification |
| `tools/scan.py`, `tools/serve.py`, `tools/inspect_docker.py` | Optional Python/browser tools |
| `tools/Icon.swift`, `resources/Info.plist`, `scripts/build-app.sh` | App icon generation, bundle configuration and build/signing |

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
