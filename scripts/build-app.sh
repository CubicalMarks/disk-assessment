#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ${CODE_SIGN_IDENTITY+x} ]]; then
  signing_identity="$CODE_SIGN_IDENTITY"
elif [[ -f .signing-identity ]]; then
  signing_identity=$(cat .signing-identity)
else
  signing_identity="-"
fi
if [[ -z "$signing_identity" || "$signing_identity" == *$'\n'* ]]; then
  printf 'Signing identity must be one nonempty line in CODE_SIGN_IDENTITY or .signing-identity.\n' >&2
  exit 1
fi

mkdir -p .build
stage_path=$(mktemp -d "$PWD/.build/app-stage.XXXXXX")
APP="$stage_path/Disk Assessment.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
cp resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp resources/cleanup-rules.json "$APP/Contents/Resources/"
mkdir -p .build/AppIcon.iconset
xcrun swift -module-cache-path "$PWD/.build/module-cache" tools/Icon.swift .build/icon.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# macOS includes SwiftUI, AppKit and the Swift runtime. No Python or server needed.
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
  -target "$(uname -m)-apple-macosx13.0" -framework AppKit -framework SwiftUI \
  src/*.swift -o "$APP/Contents/MacOS/DiskAssessment"
codesign --force --sign "$signing_identity" --timestamp=none --options runtime "$APP"
codesign --verify --deep --strict "$APP"
xcrun swift -module-cache-path "$PWD/.build/module-cache" scripts/InstallApp.swift "$APP" "$PWD/dist/Disk Assessment.app"
codesign --verify --deep --strict "$PWD/dist/Disk Assessment.app"
printf 'Built %s\n' "$PWD/dist/Disk Assessment.app"
