#!/bin/bash
# Paso 0 — puntos 4 y 6 del CLAUDE.md: verifica el binario de ffmpeg/ffprobe y la conservación de carátula.
# Uso: ./paso0-ffmpeg.sh /ruta/a/carpeta/con/ffmpeg_y_ffprobe

set -u
BIN="${1:?Indica la carpeta que contiene ffmpeg y ffprobe}"
FF="$BIN/ffmpeg"
FP="$BIN/ffprobe"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FALLOS=$((FALLOS+1)); }
FALLOS=0

# Quitar cuarentena por si se descargó del navegador
xattr -dr com.apple.quarantine "$FF" "$FP" 2>/dev/null

echo "== 4.1 Arquitectura =="
for b in "$FF" "$FP"; do
  info="$(lipo -info "$b" 2>&1)"
  [[ "$info" == *arm64* ]] && ok "$(basename "$b"): $info" || fail "$(basename "$b"): $info"
done

echo "== 4.2 Dependencias dinámicas (solo deben salir /System y /usr/lib) =="
for b in "$FF" "$FP"; do
  externas="$(otool -L "$b" | tail -n +2 | awk '{print $1}' | grep -vE '^(/System/|/usr/lib/)')"
  [[ -z "$externas" ]] && ok "$(basename "$b") sin dependencias externas" || fail "$(basename "$b") depende de: $externas"
done

echo "== 4.3 Encoders =="
ENC="$("$FF" -hide_banner -encoders 2>/dev/null)"
for e in libmp3lame flac pcm_s16le pcm_s24le pcm_f32le pcm_s16be pcm_s24be pcm_f32be libwebp; do
  grep -qE "^ [A-Z.]{6} $e " <<<"$ENC" && ok "$e" || fail "$e"
done
if grep -qE "^ [A-Z.]{6} aac_at " <<<"$ENC"; then ok "aac_at (AudioToolbox, preferido)"
elif grep -qE "^ [A-Z.]{6} aac " <<<"$ENC"; then ok "aac nativo (aac_at no disponible)"
else fail "ni aac_at ni aac"; fi

echo "== 4.4 Decoders =="
DEC="$("$FF" -hide_banner -decoders 2>/dev/null)"
for d in vorbis opus alac aac mp3 flac; do
  grep -qE "^ [A-Z.]{6} ($d|lib$d) " <<<"$DEC" && ok "$d" || fail "$d"
done

echo "== 4.5 Codificación real =="
"$FF" -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=3:sample_rate=96000" \
  -c:a pcm_s24le "$TMP/test.wav" && ok "WAV 24/96 generado" || fail "no se pudo generar WAV"
"$FF" -hide_banner -loglevel error -nostdin -i "file:$TMP/test.wav" -map 0:a:0 \
  -c:a libmp3lame -b:a 320k -ar 48000 "file:$TMP/out: con dos puntos.mp3" \
  && ok "MP3 con ':' en el nombre (prefijo file:)" || fail "MP3 con ':' en el nombre"

echo "== 6 Carátula (MP3 con cover → M4A y FLAC) =="
"$FF" -hide_banner -loglevel error -f lavfi -i "color=c=orange:s=500x500:d=1" -frames:v 1 "$TMP/cover.jpg"
"$FF" -hide_banner -loglevel error -i "$TMP/test.wav" -i "$TMP/cover.jpg" -map 0:a -map 1:v \
  -c:a libmp3lame -b:a 320k -ar 48000 -c:v copy -disposition:v:0 attached_pic -id3v2_version 3 \
  -metadata title="Prueba" "$TMP/conCover.mp3"
for dst in m4a flac; do
  case $dst in
    m4a)  codec=$(grep -qE "^ [A-Z.]{6} aac_at " <<<"$ENC" && echo aac_at || echo aac); args=(-c:a "$codec" -b:a 256k -movflags +faststart) ;;
    flac) args=(-c:a flac -compression_level 8) ;;
  esac
  "$FF" -hide_banner -loglevel error -nostdin -i "file:$TMP/conCover.mp3" -map 0:a:0 -map 0:v:0 \
    -map_metadata 0 "${args[@]}" -c:v copy -disposition:v:0 attached_pic -y "file:$TMP/out.$dst"
  pic="$("$FP" -v error -select_streams v -show_entries stream_disposition=attached_pic -of csv=p=0 "$TMP/out.$dst")"
  title="$("$FP" -v error -show_entries format_tags=title -of csv=p=0 "$TMP/out.$dst")"
  [[ "$pic" == *1* ]] && ok "$dst conserva carátula" || fail "$dst pierde carátula"
  [[ "$title" == "Prueba" ]] && ok "$dst conserva tags" || fail "$dst pierde tags"
done

echo
[[ $FALLOS -eq 0 ]] && echo "RESULTADO: todo OK" || echo "RESULTADO: $FALLOS fallo(s)"
