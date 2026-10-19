#!/usr/bin/env python3
"""Read-only metadata scan. No file contents, symlink traversal, or deletion."""
import argparse
import datetime as dt
import heapq
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time

MIB = 1024**2
GIB = 1024**3
DATA = '/System/Volumes/Data'
CLEANUP_RULES = json.loads((Path(__file__).resolve().parents[1] / 'resources' / 'cleanup-rules.json').read_text())


def display_path(path):
    if path.startswith(DATA + '/'):
        return path[len(DATA):]
    return path


def classify(path, is_dir=True):
    """Path rules identify review candidates, never prove data is disposable."""
    home = str(Path.home())
    exact = {r['path'].replace('${HOME}', home): (r['category'], r['label'], r['guidance'])
             for r in CLEANUP_RULES}
    if path in exact:
        return exact[path]
    if not is_dir and os.path.basename(path) in ('Docker.raw', 'Docker.qcow2'):
        return ('review', 'Docker disk image', 'Contains containers, images and volumes, potentially databases. Inspect docker system df -v and Docker Desktop; do not delete this file directly.')
    project_roots = (home + '/src/', home + '/.codex/worktrees/', home + '/.codex/visualizations/')
    if is_dir and path.startswith(project_roots) and os.path.basename(path) == 'node_modules':
        return ('rebuildable', 'Project dependencies', 'Confirm the manifest and lockfile exist and no manual edits are needed; reinstalling requires time and network access.')
    if is_dir and os.path.basename(path) == '.venv':
        return ('review', 'Python virtual environment', 'Check requirements or lockfile and confirm the environment is reproducible before removing it.')
    return None


class Scanner:
    def __init__(self, root, minimum=50*MIB):
        self.root = os.path.abspath(root)
        if os.path.islink(self.root) or not os.path.isdir(self.root):
            raise ValueError('Scan root must be a real directory, not a symlink.')
        self.device = os.lstat(self.root).st_dev
        self.minimum = minimum
        self.seen = set()
        self.errors = []
        self.error_count = 0
        self.mounts = []
        self.candidates = []
        self.largest = []
        self.files = 0
        self.dirs = 0
        self.symlinks = 0
        self.last_progress = time.monotonic()

    def error(self, path, exc):
        self.error_count += 1
        if len(self.errors) < 300:
            self.errors.append({'path': display_path(path), 'error': type(exc).__name__, 'detail': str(exc)})

    def walk(self, path):
        self.dirs += 1
        shown = display_path(path)
        node = {'name': os.path.basename(shown) or shown, 'path': shown, 'bytes': 0,
                'logical_bytes': 0, 'files': 0, 'children': [], 'kind': 'directory', 'errors': 0}
        try:
            entries = os.scandir(path)
        except OSError as exc:
            self.error(path, exc)
            node['errors'] = 1
            return node
        with entries:
            for entry in entries:
                try:
                    info = entry.stat(follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode):
                        self.symlinks += 1
                        continue
                    if info.st_dev != self.device:
                        self.mounts.append(display_path(entry.path))
                        continue
                    if stat.S_ISDIR(info.st_mode):
                        child = self.walk(entry.path)
                    elif stat.S_ISREG(info.st_mode):
                        identity = (info.st_dev, info.st_ino)
                        if info.st_nlink > 1:
                            if identity in self.seen:
                                continue
                            self.seen.add(identity)
                        self.files += 1
                        child = {'name': entry.name, 'path': display_path(entry.path),
                                 'bytes': info.st_blocks*512, 'logical_bytes': info.st_size,
                                 'files': 1, 'kind': 'file', 'errors': 0}
                        candidate = classify(child['path'], False)
                        if candidate:
                            self.add_candidate(child, candidate)
                        item = (child['bytes'], child['path'], info.st_size)
                        if len(self.largest) < 80:
                            heapq.heappush(self.largest, item)
                        elif item > self.largest[0]:
                            heapq.heapreplace(self.largest, item)
                    else:
                        continue
                    node['bytes'] += child['bytes']
                    node['logical_bytes'] += child['logical_bytes']
                    node['files'] += child['files']
                    node['errors'] += child['errors']
                    if child['bytes'] >= self.minimum or child['errors'] or classify(child['path'], child['kind']=='directory'):
                        node['children'].append(child)
                except OSError as exc:
                    self.error(entry.path, exc)
                    node['errors'] += 1
        node['children'].sort(key=lambda n: n['bytes'], reverse=True)
        candidate = classify(shown)
        if candidate:
            self.add_candidate(node, candidate)
        if time.monotonic() - self.last_progress > 8:
            print(f'{self.files:,} files · {self.dirs:,} directories · {shown}', file=sys.stderr, flush=True)
            self.last_progress = time.monotonic()
        return node

    def add_candidate(self, node, rule):
        if node['bytes'] < 10*MIB:
            return
        category, label, guidance = rule
        self.candidates.append({'path': node['path'], 'bytes': node['bytes'], 'files': node['files'],
                                'category': category, 'label': label, 'guidance': guidance,
                                'incomplete': bool(node.get('errors'))})


def nonoverlap(candidates):
    """Outer candidate owns nested candidates to prevent double-counting."""
    selected = []
    for c in sorted(candidates, key=lambda c: (c['path'].count('/'), c['path'])):
        if not any(c['path'].startswith(parent['path'] + '/') for parent in selected):
            selected.append(c)
    return sorted(selected, key=lambda c: c['bytes'], reverse=True)


def volume_usage(root):
    """df reports volume-used bytes; statvfs used includes APFS sibling usage."""
    result = subprocess.run(['/bin/df', '-kP', root], check=True, capture_output=True,
                            text=True, env={**os.environ, 'LC_ALL': 'C'})
    columns = result.stdout.strip().splitlines()[-1].split()
    total, used, free = (int(n)*1024 for n in columns[1:4])
    return {'total': total, 'used': used, 'free': free,
            'other_shared_usage': max(0, total-used-free), 'source': '/bin/df -kP'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default=DATA if os.path.isdir(DATA) else str(Path.home()))
    parser.add_argument('--output', default='report-data.json')
    parser.add_argument('--minimum-mib', type=float, default=50)
    args = parser.parse_args()
    start = time.monotonic()
    scanner = Scanner(args.root, int(args.minimum_mib*MIB))
    before = volume_usage(args.root)
    tree = scanner.walk(scanner.root)
    disk = volume_usage(args.root)
    disk['free_at_start'] = before['free']
    candidates = nonoverlap(scanner.candidates)
    data = {'version': 1, 'scanned_at': dt.datetime.now(dt.timezone.utc).isoformat(),
            'duration_seconds': round(time.monotonic()-start, 1), 'root': scanner.root, 'home': str(Path.home()),
            'volume': disk,
            'tree': tree, 'candidates': candidates,
            'largest_files': [{'bytes': b, 'path': p, 'logical_bytes': l} for b,p,l in sorted(scanner.largest, reverse=True)],
            'coverage': {'files': scanner.files, 'directories': scanner.dirs,
                         'symlinks_skipped': scanner.symlinks, 'mounts_skipped': scanner.mounts,
                         'error_count': scanner.error_count, 'errors': scanner.errors,
                         'tree_minimum_bytes': scanner.minimum},
            'method': ['Allocated bytes from lstat st_blocks × 512; file contents are never opened.',
                       'Symlinks and different filesystem devices are skipped. Hard links are counted once, at the first encountered path.',
                       'Directory metadata, snapshots, other volumes and inaccessible content are not included in the file sum.',
                       'APFS clones and compression can prevent allocated byte sums from equalling unique physical usage or reclaimable space.',
                       'This is a live scan, not an atomic snapshot. Paths and sizes can change during or after scanning.',
                       'Candidate labels are path-based review hints. No files are proven safe to remove. Candidate paths do not overlap.']}
    Path(args.output).write_text(json.dumps(data, ensure_ascii=True, separators=(',', ':')))
    print(json.dumps({'output': args.output, 'scanned_GiB': round(tree['bytes']/GIB, 2),
                      'candidates_GiB': round(sum(c['bytes'] for c in candidates)/GIB, 2),
                      'files': scanner.files, 'errors': scanner.error_count,
                      'duration_seconds': data['duration_seconds']}, indent=2))


if __name__ == '__main__':
    main()
