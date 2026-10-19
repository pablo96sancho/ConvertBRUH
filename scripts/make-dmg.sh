#!/bin/zsh
# DMG con hdiutil desde un staging dir (sin AppleScript/Finder).
set -euo pipefail
ROOT=${0:A:h:h}
APP=$ROOT/build/ConvertBRUH.app
[[ -d $APP ]] || "$ROOT/scripts/build-app.sh"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$ROOT/dist"
DMG=$ROOT/dist/ConvertBRUH-$VERSION.dmg

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "ConvertBRUH" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "✅ $DMG"
