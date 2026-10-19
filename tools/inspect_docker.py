#!/usr/bin/env python3
"""Append Docker's read-only storage estimates to an existing scan."""
import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', default='report-data.json')
    args = parser.parse_args()
    snapshot = Path(args.snapshot)
    data = json.loads(snapshot.read_text())
    diagnostic = {'captured_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'command': ['docker', 'system', 'df', '--format', 'json']}
    try:
        result = subprocess.run(diagnostic['command'], check=True, capture_output=True,
                                text=True, timeout=30)
        diagnostic['rows'] = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        diagnostic['error'] = str(exc)
    data['docker'] = diagnostic
    snapshot.write_text(json.dumps(data, ensure_ascii=True, separators=(',', ':')))
    print(json.dumps(diagnostic, indent=2))


if __name__ == '__main__':
    main()
