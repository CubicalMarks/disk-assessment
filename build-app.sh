#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/Disk Assessment.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
cp Info.plist "$APP/Contents/Info.plist"
cp index.html style.css treemap.js ui-model.js app.js cleanup-rules.json "$APP/Contents/Resources/"
mkdir -p .build/AppIcon.iconset
xcrun swift -module-cache-path "$PWD/.build/module-cache" Icon.swift .build/icon.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# macOS includes AppKit, WebKit and the Swift runtime. No Python or server needed.
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
  -target "$(uname -m)-apple-macosx13.0" -framework AppKit -framework WebKit \
  Scanner.swift FinderActions.swift App.swift -o "$APP/Contents/MacOS/DiskAssessment"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
