#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
  src/Scanner.swift tests/ScannerTests.swift -o .build/scanner-tests
.build/scanner-tests
PYTHONPATH="$PWD/tools${PYTHONPATH:+:$PYTHONPATH}" python3 -m unittest discover -s tests -p 'test_*.py' -v
node tests/test_treemap.js
node tests/test_ui_model.js
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/module-cache" src/Scanner.swift src/FinderActions.swift tests/FinderActionsTests.swift -o .build/finder-tests
.build/finder-tests
