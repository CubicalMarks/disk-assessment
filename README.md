# Disk assessment

A local, read-only macOS app for scanning storage and reviewing a measured report.

## Run the app

Open `dist/Disk Assessment.app` in Finder. You can copy it to Applications if you prefer. The app is self-contained: it uses a native Swift scanner and macOS’s built-in WebKit, with no Python installation, local server or package downloads.

The window opens with **Scan Mac**, **Choose Folder…**, and (after a completed scan) **View last report**. A scan shows file/folder counts, the current path, and Cancel. The resulting report contains the folder map, candidate review list and largest files. The interface uses system fonts, neutral surfaces, standard blue accents, and follows the Mac’s light/dark appearance. The map defaults to **Balanced** scaling to keep smaller folders visible; choose **Actual size** for areas proportional to allocated bytes. Balanced mode uses square-root weights with a minimum of one third of an equal share per entry. This changes display areas only: byte labels, percentages in tooltips, candidate totals, list ordering and exported reports always retain the measured sizes. Report actions let you start a new scan, show the explored folder in Finder, copy paths and export the JSON snapshot. There is no persistent toolbar, menu-bar utility or background scan.

The last completed report is saved privately at `~/Library/Application Support/Disk Assessment/last-report.json`. Cancelled scans preserve it. Scans still respect macOS privacy restrictions and report access failures. The app does not request administrator privileges or change Full Disk Access settings.

### Build locally

```sh
bash build-app.sh
bash test-app.sh
```

Building requires Apple’s Xcode command-line tools. The current build targets the architecture of the build Mac and macOS 13 or newer; it has been tested on this Apple silicon Mac. It is signed locally for personal use, not notarized for distribution to others. Build output and private reports are excluded from Git.

`Scanner.swift` implements the native metadata scan; `cleanup-rules.json` supplies the exact-path classification shared with the optional Python scanner. `App.swift` provides a normal macOS window and native folder/export dialogs. The existing local HTML/CSS/JavaScript report is bundled into the app, with native messages for scanning, copying and Finder actions. No web server is started.

## Optional browser / Python workflow

The original CLI and browser report are still supported, using Python’s standard library and plain HTML/CSS/JavaScript:

```sh
python3 scan.py
python3 serve.py
```

Open http://127.0.0.1:8765. The default scan covers `/System/Volumes/Data` on macOS, staying on the same filesystem. For a smaller scan: `python3 scan.py --root "$HOME"`. Use `--minimum-mib 10` to retain more detail. Reload snapshot in the browser after rescanning; that button does not start a new scan. The UI threshold reflects the snapshot's scan setting.

The report includes an interactive folder map/list, candidate filters, selection and path copying, largest files, and coverage errors. Selected totals describe the allocated footprint, **not guaranteed space savings**. There are no deletion commands or filesystem mutation endpoints.

## Measurement

- Reads filenames and filesystem metadata only. File contents are not opened; symlinks and other devices are skipped.
- Sums regular-file `st_blocks * 512`, rather than logical length. Hard links count once, at their first encountered location. Parent totals include entries hidden by the display threshold.
- APFS clones can share blocks across files; compression, snapshots, shared volume space, directory metadata and inaccessible paths prevent an exact reconciliation with `df` or actual recoverable space. The bar displays measured blocks, the positive difference from volume-used bytes, and available bytes. The difference is unattributed by the assessment. Other shared usage is the capacity remainder after data-volume used and available bytes; it includes sibling APFS volumes and overhead. Neither is a junk category.
- Files can change during the scan. Permission failures are reported, not bypassed. No `sudo`, entitlement changes, or automatic Full Disk Access changes.
- Candidate classification is explicit and conservative in `cleanup-rules.json` and the scanners’ suffix rules. Candidates below 10 MiB are omitted. Parent candidates own nested ones, so review totals do not double-count nested paths. Rebuildable means a review lead, not permission to delete. No last-access-time assumptions or duplicate-file claims.
- Local snapshots and protected content are outside the measured file sum. Apple manages local Time Machine snapshots as space is needed: https://support.apple.com/en-ie/102154
- Docker disk images contain mixed data, including volumes. Manage them through Docker: https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/
- Manage simulator runtimes in Xcode Settings > Components: https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components

## Privacy

`report-data.json` and `assessment.md` contain local paths and are ignored by Git. Do not publish them inadvertently. The server binds to loopback and exposes only the report assets, without directory listings. Reports use no external assets, telemetry or network services. The scanner writes only its requested output; normal OS metadata access effects still apply. Serve only snapshots you are comfortable viewing in your own browser.

For an optional read-only Docker breakdown, after scanning run `python3 inspect_docker.py`. This invokes only `docker system df --format json`, records the daemon’s estimates in the snapshot, and performs no pruning. Docker figures overlap the disk-image footprint and must not be added to candidate totals.

## Python / browser checks

```sh
python3 -m unittest -v
node --check app.js
node test_treemap.js
```

The tests cover filesystem accounting, hard links, symlinks, permission error reporting, and candidate overlap. No cleanup is performed.

Native checks cover allocated block accounting, sparse files, hardlink deduplication, symlink cycles, root validation, cancellation and compatibility with the earlier snapshot format. The optional executable mode `"dist/Disk Assessment.app/Contents/MacOS/DiskAssessment" --scan /path --output /tmp/report.json` runs the same native scanner without opening a window.

Treemap checks verify true byte proportions in Actual size mode, visibility of smaller entries in Balanced mode, unchanged byte values, area coverage and non-overlapping bounds.
