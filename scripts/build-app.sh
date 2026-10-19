#!/bin/zsh
# swift build -c release → ConvertBRUH.app → copia bin → firma ad-hoc (bin primero, luego la app).
# Uso: scripts/build-app.sh [--install]   (--install copia a /Applications y la abre)
set -euo pipefail
ROOT=${0:A:h:h}
APP=$ROOT/build/ConvertBRUH.app

[[ -x $ROOT/Resources/bin/ffmpeg && -x $ROOT/Resources/bin/ffprobe ]] || "$ROOT/scripts/fetch-ffmpeg.sh"

cd "$ROOT"
swift build -c release --arch arm64
EXE=$(swift build -c release --arch arm64 --show-bin-path)/ConvertBRUH

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/LICENSES"
cp "$EXE" "$APP/Contents/MacOS/ConvertBRUH"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/bin/ffmpeg" "$ROOT/Resources/bin/ffprobe" "$APP/Contents/Resources/bin/"
cp "$ROOT/Resources/LICENSES/"* "$APP/Contents/Resources/LICENSES/"
cp "$ROOT/Resources/MenuBar/"*.png "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/bin/"*

# Icono de la app: el .icon de Icon Composer con actool; si actool no está operativo,
# .icns desde el PNG exportado (Assets/ConvertBRUH ICON-iOS-Default-1024@1x.png)
ICON_TMP=$(mktemp -d)
cp -R "$ROOT/ConvertBRUH ICON.icon" "$ICON_TMP/AppIcon.icon"
if xcrun actool "$ICON_TMP/AppIcon.icon" --compile "$APP/Contents/Resources" --app-icon AppIcon \
     --enable-on-demand-resources NO --development-region es --target-device mac --platform macosx \
     --minimum-deployment-target 13.0 --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null 2>&1 \
   && [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  echo "Icono: compilado desde ConvertBRUH ICON.icon con actool"
else
  swift "$ROOT/scripts/make-icns.swift" "$ROOT/Assets/ConvertBRUH ICON-iOS-Default-1024@1x.png" "$ICON_TMP/AppIcon.iconset" >/dev/null
  iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
  echo "Icono: .icns desde el PNG exportado (actool no disponible; ver 'sudo xcodebuild -runFirstLaunch')"
fi
rm -rf "$ICON_TMP"
xattr -cr "$APP"

codesign -s - -f "$APP/Contents/Resources/bin/ffmpeg" "$APP/Contents/Resources/bin/ffprobe"
codesign -s - -f "$APP"
codesign --verify --deep --strict "$APP"
echo "✅ $APP"

if [[ ${1:-} == --install ]]; then
  pkill -x ConvertBRUH || true
  rm -rf /Applications/ConvertBRUH.app
  cp -R "$APP" /Applications/
  open /Applications/ConvertBRUH.app
  echo "✅ Instalada en /Applications y abierta"
fi
