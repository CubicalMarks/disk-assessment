#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
  Scanner.swift ScannerTests.swift -o .build/scanner-tests
.build/scanner-tests
python3 -m unittest -v
node --check app.js
codesign --verify --deep --strict "dist/Disk Assessment.app"
