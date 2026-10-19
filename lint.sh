#!/bin/bash
# Lightweight source validation; uses the same tools as the build and tests.
set -euo pipefail
cd "$(dirname "$0")"

for tool in node python3 xcrun git; do
  command -v "$tool" >/dev/null || { printf 'Missing required tool: %s\n' "$tool" >&2; exit 1; }
done

for source in ./*.sh; do bash -n "$source"; done
for source in ./*.js; do node --check "$source"; done
for source in ./*.swift; do xcrun swiftc -frontend -parse "$source"; done
python3 - <<'PY'
import json
import plistlib
from pathlib import Path

for source in sorted(Path('.').glob('*.py')):
    compile(source.read_bytes(), str(source), 'exec')
json.loads(Path('cleanup-rules.json').read_text())
plistlib.loads(Path('Info.plist').read_bytes())
PY

git diff --check
git diff --cached --check
printf 'Source checks passed: shell, JavaScript, Swift, Python, JSON, plist and changed-line whitespace.\n'
