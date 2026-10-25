#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

python_path="$PWD/.build/dmg-tools/bin/python"
if [[ ! -x "$python_path" ]]; then
    python3 -m venv .build/dmg-tools
fi
"$python_path" -m pip install --disable-pip-version-check -r scripts/dmg-requirements.txt

# Build first so a failed build never packages a stale app.
bash scripts/build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' 'dist/Disk Assessment.app/Contents/Info.plist')
stage_path=$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")
mount_path="$stage_path/mounted"
image_path="$stage_path/installer-rw.dmg"
output_path="$PWD/dist/Disk-Assessment-$version-$(uname -m).dmg"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        hdiutil detach "$mount_path" >/dev/null || true
    fi
}
trap cleanup EXIT

mkdir -p "$stage_path/content/.background" "$mount_path"
ditto 'dist/Disk Assessment.app' "$stage_path/content/Disk Assessment.app"
ln -s /Applications "$stage_path/content/Applications"
swift -module-cache-path .build/module-cache scripts/DMGBackground.swift "$stage_path/content/.background/installer.png"
hdiutil create -quiet -volname 'Disk Assessment' -fs HFS+ -format UDRW -srcfolder "$stage_path/content" "$image_path"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$mount_path" "$image_path"
mounted=true
"$python_path" scripts/layout-dmg.py "$mount_path"
test -s "$mount_path/.DS_Store"
codesign --verify --deep --strict "$mount_path/Disk Assessment.app"
sync
hdiutil detach -quiet "$mount_path"
mounted=false
hdiutil convert -quiet "$image_path" -format UDZO -imagekey zlib-level=9 -o "$stage_path/installer.dmg"
hdiutil verify "$stage_path/installer.dmg"
# Publish only a complete, verified image; retain any prior output on failure.
mv -f "$stage_path/installer.dmg" "$output_path"
(cd dist && shasum -a 256 "$(basename "$output_path")" > "$(basename "$output_path").sha256")
printf 'Built: %s\n' "$output_path"
