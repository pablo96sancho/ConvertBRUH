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
chmod +x "$APP/Contents/Resources/bin/"*
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
