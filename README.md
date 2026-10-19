# Disk assessment

A local, read-only macOS storage assessment. Python standard library and plain HTML/CSS/JavaScript; no package installation or external services.

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
- Candidate classification is explicit and conservative in `classify()`. Candidates below 10 MiB are omitted. Parent candidates own nested ones, so review totals do not double-count nested paths. Rebuildable means a review lead, not permission to delete. No last-access-time assumptions or duplicate-file claims.
- Local snapshots and protected content are outside the measured file sum. Apple manages local Time Machine snapshots as space is needed: https://support.apple.com/en-ie/102154
- Docker disk images contain mixed data, including volumes. Manage them through Docker: https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/
- Manage simulator runtimes in Xcode Settings > Components: https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components

## Privacy

`report-data.json` and `assessment.md` contain local paths and are ignored by Git. Do not publish them inadvertently. The server binds to loopback and exposes only the report's four assets, without directory listings. Reports use no external assets, telemetry or network services. The scanner writes only its requested output; normal OS metadata access effects still apply. Serve only snapshots you are comfortable viewing in your own browser.

For an optional read-only Docker breakdown, after scanning run `python3 inspect_docker.py`. This invokes only `docker system df --format json`, records the daemon’s estimates in the snapshot, and performs no pruning. Docker figures overlap the disk-image footprint and must not be added to candidate totals.

## Checks

```sh
python3 -m unittest -v
node --check app.js
```

The tests cover filesystem accounting, hard links, symlinks, permission error reporting, and candidate overlap. No cleanup is performed.
