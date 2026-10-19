#!/bin/zsh
# Descarga los builds estáticos arm64 de ffmpeg/ffprobe (Martin Riedl, ver docs/paso0.md) a Resources/bin.
set -euo pipefail
ROOT=${0:A:h:h}
BIN=$ROOT/Resources/bin
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$BIN"
for b in ffmpeg ffprobe; do
  echo "Descargando $b…"
  curl -fsSL -o "$TMP/$b.zip" "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/$b.zip"
  mkdir -p "$TMP/$b"
  unzip -o -q "$TMP/$b.zip" -d "$TMP/$b"
  install -m 755 "$TMP/$b/$b" "$BIN/$b"
done
xattr -cr "$BIN"

# Comprobaciones del Paso 0
for b in ffmpeg ffprobe; do
  lipo -info "$BIN/$b" | grep -q arm64 || { echo "❌ $b no es arm64"; exit 1; }
  externas=$(otool -L "$BIN/$b" | tail -n +2 | awk '{print $1}' | grep -vE '^(/System/|/usr/lib/)' || true)
  [[ -z "$externas" ]] || { echo "❌ $b depende de: $externas"; exit 1; }
done
"$BIN/ffmpeg" -hide_banner -version | head -1
echo "✅ ffmpeg y ffprobe listos en $BIN"
