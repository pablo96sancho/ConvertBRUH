#!/bin/zsh
# Monta Paso0.app (con ffmpeg/ffprobe dentro), firma ad-hoc y lo instala en /Applications.
# Uso: ./build.sh /carpeta/con/ffmpeg_y_ffprobe
set -e
DIR=${0:A:h}
BIN=${1:?Indica la carpeta que contiene ffmpeg y ffprobe}
OUT=$DIR/build/Paso0.app

rm -rf $OUT
mkdir -p $OUT/Contents/MacOS $OUT/Contents/Resources/bin
swiftc -O -target arm64-apple-macos13 -o $OUT/Contents/MacOS/Paso0 $DIR/main.swift
cp $BIN/ffmpeg $BIN/ffprobe $OUT/Contents/Resources/bin/
chmod +x $OUT/Contents/Resources/bin/*
xattr -cr $OUT
cat > $OUT/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.djokobeatz.convertbruh.paso0</string>
<key>CFBundleName</key><string>Paso0</string>
<key>CFBundleExecutable</key><string>Paso0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
# Firmar primero los binarios internos y luego el bundle
codesign -s - -f $OUT/Contents/Resources/bin/ffmpeg $OUT/Contents/Resources/bin/ffprobe
codesign -s - -f $OUT
codesign -dvvv $OUT 2>&1 | grep -E "^CDHash=" || true

pkill -x Paso0 || true
rm -rf /Applications/Paso0.app
cp -R $OUT /Applications/
echo "Instalado en /Applications/Paso0.app"
