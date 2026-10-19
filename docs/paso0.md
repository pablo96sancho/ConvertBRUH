# Paso 0 — Resultados

Máquina: macOS 27.0.1, Apple Silicon, Swift 6.4. Fecha: 2026-10-19.
Prototipos: `ConvertBRUH-Paso0/` (paquete SwiftPM de consola y `App/` como `.app` firmado ad-hoc).

| # | Punto | Resultado |
|---|---|---|
| 1 | Monitor global sin Accesibilidad | ✅ `AXIsProcessTrusted=false` y se reciben `leftMouseDown/Dragged/Up` durante un arrastre de Finder. `NSEvent.modifierFlags` refleja Shift en tiempo real (incluso pulsado a mitad del arrastre). Shift+Cmd da flags `0x120000` → hay que filtrar por la combinación exacta |
| 2 | Drag pasteboard | ✅ `changeCount` cambia (p. ej. 696 → 697) unos pocos eventos después del `mouseDown`; `readObjects(.urlReadingFileURLsOnly)` devuelve la URL, incluso con `@` y espacios en la ruta. Tipos: `public.file-url`, `NSFilenamesPboardType`… Probado desde Finder. Escritorio y Ableton: pendiente, se valida con la app real |
| 3 | Panel creado a mitad de arrastre | ✅ `NSPanel` `.nonactivatingPanel` mostrado con `orderFrontRegardless()` recibe `draggingEntered/Updated/Exited` y `performDragOperation` con las URLs. `NSApp.isActive` sigue en `false` |
| 4 | Binario ffmpeg | ✅ Build estático de **Martin Riedl** (`https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/{ffmpeg,ffprobe}.zip`), ffmpeg 9.0.2, GPL v3. `lipo`: arm64. `otool -L`: solo `/System` y `/usr/lib`. Encoders: libmp3lame, flac, pcm_s16le/s24le/f32le, pcm_s16be/s24be/f32be, libwebp, aac_at, aac. Decoders: vorbis, opus, alac, aac, mp3. Se ejecuta desde dentro del `.app`: pendiente de confirmar en la app real |
| 5 | WebP vía ImageIO | ❌ `org.webmproject.webp` **no** está en `CGImageDestinationCopyTypeIdentifiers()` (sí se puede leer) → fallback con ffmpeg `libwebp`, probado OK |
| 6 | Carátula | ✅ MP3 con carátula y tags → MP3, M4A (`aac_at`) y FLAC conservan `attached_pic` y los tags con los comandos de §5.1 |
| 7 | TCC | ⏳ Pendiente (se valida con la app real) |
| 8 | Login item | ⏳ Pendiente (se valida con la app real en `/Applications`) |
| 9 | AirDrop / Float | ⏳ Pendiente (se valida al implementar el anillo de Acciones) |
| 10 | Metadata de imagen | ✅ `CGImageDestinationCopyImageSource` con `kCGImageDestinationMetadata` (solo orientación), `MergeMetadata=false`, `ShouldExcludeXMP/GPS=true` → sin GPS ni EXIF, orientación conservada y **datos JPEG idénticos byte a byte** (sin recodificar). Se pierde el DPI |
| 11 | PDF | ✅ `CGContext(consumer:mediaBox:)` con la imagen ya orientada; mediaBox = píxeles × 72 / DPI |

## Otros hallazgos

- **Bit depth en ffprobe:** FLAC 24 bit → `sample_fmt=s32`, `bits_per_raw_sample=24`. WAV 24 bit → `bits_per_sample=24`. Hay que mirar ambos campos.
- **Remuestreo:** FLAC 24/96 → WAV 24/96 ✅; MP3 y M4A con `-ar 48000` → 48 kHz ✅.
- **FLAC 24:** `-sample_fmt s32 -bits_per_raw_sample 24` produce FLAC de 24 bit ✅.
- **Normalize:** `loudnorm` en dos pasadas con `linear=true` → −14,0 LUFS exactos. Sube el audio a 192 kHz internamente: hay que forzar `-ar` con el original.
- **Encoders extra disponibles** (por si algún día se amplía): wmav2, libopus, libvorbis; ImageIO escribe HEIC, TIFF, BMP, AVIF y PDF.
