#!/bin/bash
# Compila ConvertBRUH en modo release y genera ConvertBRUH-Installer.dmg
# (hdiutil desde un staging dir; sin AppleScript/Finder).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="ConvertBRUH"
DMG_NAME="ConvertBRUH-Installer.dmg"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"

echo "🔨 Compilando ConvertBRUH (release)..."
"$ROOT_DIR/scripts/build-app.sh"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"

echo "🗂  Preparando contenido del DMG..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$ROOT_DIR/$DMG_NAME"

echo "💿 Creando $DMG_NAME..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$ROOT_DIR/$DMG_NAME"

rm -rf "$STAGING_DIR"
echo "✅ Instalador creado: $ROOT_DIR/$DMG_NAME"
