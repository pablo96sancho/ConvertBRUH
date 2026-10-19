# ConvertBRUH — CLAUDE.md

App de barra de menú para macOS que actúa sobre archivos **mientras los arrastras**. Según la tecla que mantengas pulsada, aparece un anillo alrededor del cursor:

| Tecla durante el arrastre | Anillo | Qué hace |
|---|---|---|
| **Shift** | **Convertir** | Crea una copia en otro formato junto al original |
| **Option** | **Acciones** | AirDrop, Copy, Copy Path, Move, Float |
| **Shift + Option** | **Herramientas** | Procesados automáticos (Normalize, Compress, Channels, Metadata) |

Sueltas el archivo sobre una porción y se ejecuta. Todo es local y **el original nunca se modifica** (salvo *Move*, que lo mueve a propósito).

Inspirada en Tangerine (fotos en `Referencias/`). Sin ventana de ajustes ni editores visuales en v1.

---

## 1. Stack y restricciones

- **Lenguaje:** Swift 5.9+ con SwiftUI + AppKit. Sin dependencias Swift de terceros.
- **Target:** macOS 13+, arm64 (Apple Silicon).
- **Build:** Swift Package Manager. Un script monta el `.app`, firma ad-hoc (`codesign -s -`) y genera el DMG con `hdiutil` desde un staging dir. **No usar AppleScript/Finder para el DMG.**
- **Tipo de app:** app agente con `LSUIElement = true` (sin Dock). Sin sandbox, porque tiene que escribir junto a archivos de cualquier carpeta.
- **Motor de audio:** binarios estáticos de `ffmpeg` y `ffprobe` dentro de `ConvertBRUH.app/Contents/Resources/bin/`. Se invocan con `Process`, **nunca a través de una shell**.
- **Idioma:** UI y comentarios del código en **español**. Las etiquetas de las porciones (MP3, AIRDROP, NORMALIZE…) van en inglés y mayúsculas, como en las referencias.
- **Logging:** `os.Logger` con subsystem `com.djokobeatz.convertbruh`.

---

## 2. Paso 0 — Verificación empírica (OBLIGATORIO antes de implementar)

Resultados en `docs/paso0.md`. **Si algo falla, parar y consultar antes de buscar alternativas.** Prototipos en `ConvertBRUH-Paso0/`.

1. **Monitor global de arrastre** sin permiso de Accesibilidad; `NSEvent.modifierFlags` fiable durante el arrastre para **Shift, Option y Shift+Option**.
2. **Drag pasteboard:** `changeCount` cambia respecto a `leftMouseDown` y `readObjects(... .urlReadingFileURLsOnly)` devuelve las URLs. Probar desde Finder, Escritorio y Ableton.
3. **Panel creado a mitad de arrastre** (`.nonactivatingPanel`) recibe `draggingEntered`/`draggingUpdated`/`performDragOperation`.
4. **Binario ffmpeg:** arm64, `otool -L` solo con sistema, encoders/decoders necesarios, ejecutable desde dentro del `.app` firmado ad-hoc.
5. **WebP vía ImageIO:** ¿`CGImageDestinationCopyTypeIdentifiers()` incluye `org.webmproject.webp`?
6. **Carátula** conservada al convertir a MP3, M4A y FLAC.
7. **TCC:** prompts al escribir en Escritorio, Documentos, Descargas, iCloud Drive y volúmenes externos; ¿cada rebuild ad-hoc resetea los permisos?
8. **Login item:** `SMAppService.mainApp.register()` con firma ad-hoc y la app en `/Applications`.
9. **Acciones:** `NSSharingService(named: .sendViaAirDrop)` funciona desde una app agente sin activar; un `NSPanel` flotante actúa como `NSDraggingSource` de file URLs hacia Finder y Ableton (Float).
10. **Metadata de imagen:** `CGImageDestinationCopyImageSource` con las opciones de borrado elimina EXIF/GPS **sin recodificar** un JPEG.
11. **PDF:** una imagen se escribe como PDF de una página con `CGContext(consumer:mediaBox:)` conservando la resolución.

---

## 3. Interacción

### 3.1 Activación
1. En `leftMouseDown` se guarda el `changeCount` del drag pasteboard y la posición.
2. En `leftMouseDragged`, el anillo se muestra si:
   - el `changeCount` ha cambiado;
   - el pasteboard contiene file URLs;
   - hay **Shift**, **Option** o ambos pulsados (sin Command ni Control);
   - el cursor se ha movido ≥ 8 pt.
3. El tipo de anillo depende de los modificadores: Shift → Convertir, Option → Acciones, Shift+Option → Herramientas.
4. **Mientras está visible, el anillo sigue los modificadores**: si cambian a otra combinación válida, se cambia de anillo con una transición corta. Si se sueltan todas las teclas, se queda el último anillo hasta `leftMouseUp`.
5. El anillo se centra en el cursor y se recoloca dentro del `visibleFrame` de la pantalla actual.
6. Si al soltar el ratón no se ha hecho drop en una porción, el anillo se cierra sin hacer nada.
7. Soltar en el centro del anillo = cancelar.
8. Si para el anillo pedido no hay ninguna porción válida, **no aparece nada** (o, si ya estaba visible, se cierra).

### 3.2 Panel
- `NSPanel` con `styleMask: [.borderless, .nonactivatingPanel]` y `level = .popUpMenu`.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`.
- `hasShadow = true`, fondo transparente y `registerForDraggedTypes([.fileURL])`.
- Contenido en SwiftUI dentro de un `NSHostingView`.
- **No debe robar el foco ni activar la app.** (Excepción: *Move* activa la app para mostrar el diálogo de carpeta.)

### 3.3 Aspecto del anillo (ver `Referencias/`)
- Diámetro de unos 300 pt. Disco exterior negro con N porciones iguales en forma de sector anular con esquinas muy redondeadas y separación de unos 6 pt.
- Porciones de material translúcido claro (efecto cristal) sobre el disco oscuro; texto blanco en negrita y mayúsculas.
- Anillos de Acciones y Herramientas: **SF Symbol encima de la etiqueta**. Anillo de Convertir: solo texto.
- La primera porción va centrada arriba y el resto sigue el sentido horario.
- **Centro:** cápsula con el tamaño total de los archivos arrastrados (`ByteCountFormatter`, `.file`).
- **Hover:** la porción bajo el cursor se ilumina y escala un poco. Se calcula por ángulo y radio desde el centro en `draggingUpdated`.
- `performDragOperation` devuelve `true` y la operación es `.copy` (`.move` en Move).

### 3.4 Clasificación de archivos
Con `UTType` del archivo (`resourceValues(forKeys: [.contentTypeKey])`):

| Tipo | Conformidad |
|---|---|
| Audio: WAV, AIFF, FLAC, M4A, MP3, OGG, OPUS… | `.audio` |
| Vídeo: MP4, MOV… (se usa su pista de audio) | `.movie` / `.audiovisualContent` |
| Imagen: PNG, JPG, HEIC, WEBP, TIFF, GIF, BMP… | `.image` |
| Otro (carpetas, documentos…) | — (solo anillo de Acciones) |

**Regla general para Convertir y Herramientas:** solo aparecen las porciones válidas para *todos* los archivos convertibles. Los no válidos se ignoran en silencio. Si no queda ninguno, no hay anillo.

### 3.5 Anillo CONVERTIR (Shift)

| Entrada | Porciones |
|---|---|
| Audio / vídeo con audio | MP3 · WAV · M4A · FLAC · AIFF |
| Imagen | JPG · PNG · WEBP · PDF |

- Se oculta la porción del formato de origen cuando todos los archivos comparten ese formato.
- Vídeo sin pista de audio → no válido.

### 3.6 Anillo ACCIONES (Option)
Vale para **cualquier archivo o carpeta**.

| Porción | SF Symbol | Comportamiento |
|---|---|---|
| **AIRDROP** | `airplayaudio` (o `dot.radiowaves.up.forward`) | `NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)` |
| **COPY** | `doc.on.doc` | Escribe las file URLs en `NSPasteboard.general` (se pueden pegar en Finder, Slack, etc.) |
| **COPY PATH** | `doc.text` | Copia las rutas POSIX como texto, una por línea |
| **MOVE** | `folder` | `NSOpenPanel` para elegir carpeta (activa la app) → `moveItem` con la regla de colisiones de §4. Si el destino está en otro volumen, se copia y luego se borra el original solo si la copia terminó bien |
| **FLOAT** | `pin` | Ventana flotante siempre encima con la miniatura (`QLThumbnailGenerator`) y el nombre; se puede volver a arrastrar a cualquier app (Finder, Ableton, navegador). Con varios archivos, una pila con contador. Botón ✕ para cerrar; se cierra sola tras un arrastre que acabe en `.move` |

Orden horario desde arriba: AIRDROP · FLOAT · COPY · MOVE · COPY PATH.

### 3.7 Anillo HERRAMIENTAS (Shift + Option)
Procesados automáticos, sin ventanas. Generan un archivo nuevo junto al original con sufijo (`beat_normalized.wav`).

**Audio / vídeo con audio**

| Porción | SF Symbol | Proceso | Salida |
|---|---|---|---|
| **NORMALIZE** | `waveform` | `loudnorm` en dos pasadas: −14 LUFS integrados, pico real −1 dBTP. Primera pasada con `print_format=json` para medir; segunda con `measured_*`, `offset` y `linear=true`. **Siempre `-ar <sample rate original>`** (loudnorm sube a 192 kHz internamente) | Mismo formato que el original (vídeo → WAV), `_normalized` |
| **COMPRESS** | `arrow.down.right.and.arrow.up.left` | MP3 VBR `-q:a 5` (~130 kbps). Sample rate según §5.1 | `.mp3`, `_compressed` |
| **CHANNELS** | `hifispeaker.2` | Estéreo/multicanal → mono (`-ac 1`); mono → estéreo duplicado (`-ac 2`) | Mismo formato, `_mono` / `_stereo` |
| **METADATA** | `tag` | Borra tags y carátula sin recodificar: `-map 0:a:0 -c copy -map_metadata -1` | Mismo formato, `_clean` |

- Para salidas sin pérdida, la resolución de bit depth sigue §5.1.
- En lote mixto (mono + estéreo), CHANNELS se decide por archivo.

**Imagen**

| Porción | SF Symbol | Proceso | Salida |
|---|---|---|---|
| **COMPRESS** | `arrow.down.right.and.arrow.up.left` | Lado mayor máx. 2560 px. Sin transparencia → JPG calidad 0.7. Con transparencia → PNG | `_compressed` |
| **METADATA** | `tag` | Quita EXIF, GPS, IPTC y XMP. JPEG/HEIC/PNG/TIFF: sin recodificar (`CGImageDestinationCopyImageSource`). La orientación se conserva | Mismo formato, `_clean` |

Orden horario desde arriba: audio → NORMALIZE · COMPRESS · CHANNELS · METADATA; imagen → COMPRESS · METADATA.

---

## 4. Salida

- **Destino:** la misma carpeta que el original, con el mismo nombre base y la nueva extensión (`beat.wav` → `beat.mp3`) o el sufijo de la herramienta (`beat_normalized.wav`).
- **Colisión:** `beat (1).mp3`, `beat (2).mp3`… Nunca se sobrescribe nada.
- **Escritura atómica:**
  1. Se escribe en un directorio temporal del mismo volumen: `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destino, create: true)`.
  2. Al terminar bien, `moveItem` al nombre final, que se resuelve justo en ese momento.
  3. Si falla, se borra el temporal. **No debe quedar nunca un archivo a medias.**
- **Carpeta sin permiso de escritura** (volumen de solo lectura, DMG, permiso denegado): se escribe en `~/Downloads` con la misma regla de nombres y se avisa en el estado de error (§6).
- **El original no se modifica nunca**, ni sus metadatos ni su fecha (salvo Move).

---

## 5. Conversión

### 5.1 Audio (ffmpeg)

**Reglas comunes**
- Antes de convertir, `ffprobe -v error -of json -show_streams -show_format "file:<ruta>"` para sacar duración, códec, `sample_rate`, `channels`, `bits_per_raw_sample`/`bits_per_sample`/`sample_fmt` y si hay stream de imagen adjunta (`disposition.attached_pic == 1`).
  - Ojo (Paso 0): FLAC de 24 bit se reporta como `sample_fmt=s32` + `bits_per_raw_sample=24`; WAV de 24 bit como `bits_per_sample=24`. Mirar ambos campos.
- Rutas **siempre con prefijo `file:`**.
- Flags base: `-hide_banner -nostdin -loglevel error -progress pipe:1 -nostats -i file:<in>`. Salida al temporal con `-y`.
- Solo el primer stream de audio: `-map 0:a:0`. Si no hay audio → error "El archivo no tiene audio".
- `-map_metadata 0` para conservar tags (salvo METADATA).
- **Carátula:** solo si el origen tiene `attached_pic` y el destino es MP3, M4A o FLAC: `-map 0:v:<idx> -c:v copy -disposition:v:0 attached_pic`. En WAV/AIFF, o si el origen es un vídeo, `-vn`.
- **Canales:** se mantienen. Más de 2 canales hacia MP3 → `-ac 2`.
- **Sample rate:** se mantiene, salvo en MP3 y M4A: si es mayor de 48 kHz, 88.2/176.4 → 44100 y 96/192 → 48000 (`-ar`).

**Bit depth para salidas sin pérdida**
- Origen sin pérdida (WAV, AIFF, FLAC, ALAC) → se conserva: 16 → 16, 24 → 24, 32 float → 32 float. FLAC no admite float: 32f → 24.
- Origen con pérdida (MP3, AAC, OGG, OPUS) → 16 bits.

| Destino | Códec / ajustes |
|---|---|
| **MP3** | `-c:a libmp3lame -b:a 320k -id3v2_version 3` |
| **M4A** | `-c:a aac_at -b:a 256k` (fallback `aac`) `-movflags +faststart` |
| **WAV** | `pcm_s16le` / `pcm_s24le` / `pcm_f32le` |
| **FLAC** | `-c:a flac -compression_level 8`, más `-sample_fmt s16` o `s32 -bits_per_raw_sample 24` |
| **AIFF** | `pcm_s16be` / `pcm_s24be` / `pcm_f32be` |

### 5.2 Imagen (ImageIO)

**Lectura:** `CGImageSourceCreateWithURL`. Primer frame; orientación EXIF aplicada (`kCGImageSourceCreateThumbnailWithTransform` sin reducir); se mantienen resolución y perfil de color.

| Destino | Ajustes |
|---|---|
| **JPG** | `kCGImageDestinationLossyCompressionQuality = 0.9`. Transparencia aplanada sobre **blanco**. Se conservan EXIF y GPS |
| **PNG** | Sin pérdida |
| **WEBP** | ImageIO no escribe WebP (Paso 0) → PNG temporal → `ffmpeg -i file:<tmp.png> -c:v libwebp -quality 85 -frames:v 1 file:<out>` → borrar PNG temporal |
| **PDF** | Un PDF de una página por imagen. `CGContext(consumer:mediaBox:)` con mediaBox = tamaño en píxeles × 72 / DPI de la imagen (72 si no hay DPI). Imagen dibujada sin recomprimir el contenido más allá de lo que haga Quartz |

### 5.3 Cola
- `actor ConversionQueue` con **máximo 4 trabajos simultáneos**, resto en FIFO. La usan Convertir y Herramientas.
- Cada `Process` de ffmpeg queda registrado; en `applicationWillTerminate` se terminan y se borran sus temporales.
- **Progreso de audio:** `out_time_us` de `-progress pipe:1` frente a la duración de ffprobe (NORMALIZE: 50 % por pasada).
- **Progreso de imagen:** 0 o 100.

---

## 6. Feedback

- **Durante el trabajo:** tras el drop, el anillo se queda visible y el centro muestra el progreso agregado (`37 %`, o `2/5` en lote). Las porciones se atenúan y no aceptan otro drop.
- **Al terminar bien:** fade y `NSWorkspace.shared.activateFileViewerSelecting(urls)` con los archivos creados (no en COPY, COPY PATH, AIRDROP ni FLOAT; en COPY/COPY PATH el centro muestra `✓` medio segundo).
- **Si falla:** el centro muestra `Error` en rojo 2 s y se cierra; el mensaje se guarda en "Último error" del menú. En lote con fallos parciales se revelan los buenos y se guarda el resumen.
- Mientras hay trabajos se pueden lanzar más. El icono de la barra indica trabajos activos.
- **Sin notificaciones del sistema.**

### Menú de la barra (`MenuBarExtra`)
- Icono SF Symbol `arrow.triangle.2.circlepath`; variante animada/rellena con trabajos.
- `Conversiones en curso: N` (deshabilitado, solo si N > 0)
- `Último error: …` (solo si hay; clic → copia al portapapeles)
- `Abrir al iniciar sesión` (toggle con `SMAppService.mainApp`)
- `Cómo se usa` (alerta: "Arrastra un archivo y mantén Shift para convertir, Option para acciones o Shift+Option para herramientas")
- `Salir de ConvertBRUH`

---

## 7. Casos límite

| Caso | Comportamiento |
|---|---|
| Archivo de iCloud no descargado | `ubiquitousItemDownloadingStatus != .current` → "Descarga el archivo de iCloud primero" (Convertir/Herramientas) |
| Archivo corrupto o códec no soportado | Error con el `stderr` resumido (máx. 200 caracteres) |
| Vídeo sin pista de audio | No válido para Convertir/Herramientas |
| Carpetas en el arrastre | Solo cuentan para Acciones |
| Nombres con `:`, `@`, emojis, espacios o acentos | Prefijo `file:` y `Process.arguments` (sin shell) |
| Archivo borrado o movido entre drag y drop | "El archivo ya no existe" |
| Disco lleno | Error y se borra el temporal |
| Arrastrar sin modificadores, o con Command/Control | Comportamiento normal del sistema; la app no hace nada |
| Varios monitores | Anillo en la pantalla del cursor, dentro de su `visibleFrame` |
| Option-arrastre en Finder | Finder cambiaría a copiar, pero el drop lo recibe el anillo; si se suelta fuera del anillo, manda el comportamiento normal de Finder |

---

## 8. Estructura del proyecto

```
ConvertBRUH/
├── Package.swift
├── CLAUDE.md
├── docs/paso0.md
├── Referencias/                       // fotos de Tangerine
├── ConvertBRUH-Paso0/                 // prototipos del Paso 0
├── Sources/ConvertBRUH/
│   ├── App/
│   │   ├── ConvertBRUHApp.swift       // MenuBarExtra, ciclo de vida
│   │   └── AppState.swift             // trabajos activos, último error
│   ├── Arrastre/
│   │   └── DragMonitor.swift          // monitores globales + drag pasteboard + modificadores → tipo de anillo
│   ├── Anillo/
│   │   ├── RingPanel.swift            // NSPanel + NSDraggingDestination
│   │   ├── RingView.swift             // SwiftUI: porciones, centro, progreso
│   │   ├── RingGeometry.swift         // punto → índice de porción
│   │   └── RingSlice.swift            // modelo de porción (etiqueta, símbolo, acción)
│   ├── Conversion/
│   │   ├── FileKind.swift             // clasificación por UTType
│   │   ├── TargetFormat.swift         // formatos + porciones disponibles
│   │   ├── MediaProbe.swift           // ffprobe → struct
│   │   ├── AudioConverter.swift       // argumentos ffmpeg de conversión
│   │   ├── ImageConverter.swift       // ImageIO + WebP + PDF
│   │   ├── FFmpegRunner.swift         // Process, progreso, cancelación
│   │   └── ConversionQueue.swift      // actor, máx. 4
│   ├── Herramientas/
│   │   ├── AudioTools.swift           // Normalize, Compress, Channels, Metadata (argumentos puros)
│   │   └── ImageTools.swift           // Compress, Metadata
│   ├── Acciones/
│   │   ├── FileActions.swift          // AirDrop, Copy, Copy Path, Move
│   │   └── FloatPanel.swift           // ventana flotante arrastrable
│   ├── Salida/
│   │   └── OutputWriter.swift         // nombres, temporal, move atómico, fallback Descargas
│   └── Soporte/
│       ├── LoginItem.swift
│       └── Log.swift
├── Tests/ConvertBRUHTests/
├── Resources/
│   ├── Info.plist
│   ├── LICENSES/                      // aviso GPL de ffmpeg + enlace a fuentes
│   └── bin/ffmpeg, bin/ffprobe        // no se versionan; los descarga scripts/fetch-ffmpeg.sh
└── scripts/
    ├── fetch-ffmpeg.sh                // descarga build estático arm64 (ver docs/paso0.md)
    ├── build-app.sh                   // swift build -c release → .app → bin → codesign ad-hoc (bin primero)
    └── make-dmg.sh                    // hdiutil desde staging dir
```

`AudioConverter`, `AudioTools` y `OutputWriter` deben ser **funciones puras testeables**; argumentos y nombres se cubren con `swift test` sin ejecutar ffmpeg.

---

## 9. Fuera de alcance (v1)

- Herramientas con editor visual: Trim, Crop, Annotate, Edit, Redact, Bleep, Visualize, Add BG
- Acción Terminal
- Ventana de ajustes o elección de calidad
- Sustituir el original
- Salida de vídeo
- OGG, OPUS, WMA, HEIC, TIFF, AVIF y BMP como formatos de salida (sí se aceptan como entrada)
- Notificaciones
- Sandbox, App Store y notarización
- Intel/Rosetta

---

## 10. Criterios de aceptación

1. Shift + arrastre de un `.wav` → MP3 · M4A · FLAC · AIFF. Soltar en MP3 → `nombre.mp3` a 320 kbps junto al original, seleccionado en Finder.
2. `.flac` 24 bit/96 kHz → WAV 24/96; MP3 48 kHz; M4A 48 kHz.
3. MP3 con carátula → M4A y FLAC conservan carátula y tags.
4. `.mov` muestra el anillo de audio y genera solo el audio.
5. `.heic` muestra JPG · PNG · WEBP · PDF; el JPG respeta la orientación.
6. PNG con transparencia → JPG con fondo blanco.
7. Repetir la misma conversión genera `nombre (1).ext`.
8. 6 archivos a la vez → 4 en paralelo, `n/6` en el centro, los 6 seleccionados al terminar.
9. Desde un DMG montado → la salida va a `~/Downloads`.
10. Sin modificadores no aparece nada. Texto o carpetas con Shift tampoco.
11. Soltar en el centro no crea ni cambia nada.
12. Matar la app a mitad de un trabajo no deja archivos parciales.
13. La app no aparece en el Dock y no roba el foco cuando sale el anillo.
14. Option + arrastre de una carpeta → anillo de Acciones; COPY PATH deja la ruta en el portapapeles.
15. FLOAT de un `.wav` → miniatura flotante que se puede arrastrar a Ableton y crea el clip.
16. MOVE a otra carpeta con un archivo del mismo nombre → `nombre (1).ext`.
17. Shift + Option sobre un WAV → NORMALIZE produce `nombre_normalized.wav` a −14 LUFS (±0,5).
18. METADATA sobre un JPG con GPS → `nombre_clean.jpg` sin GPS y con los mismos píxeles.
19. Cambiar de Shift a Shift+Option durante el arrastre cambia el anillo sin cerrarlo.

---

## 11. Forma de trabajar

- Empezar por el **Paso 0** y no implementar nada de §3–§6 hasta tenerlo validado.
- Orden de implementación:
  1. `DragMonitor` (con modificadores) + panel vacío que aparece y desaparece
  2. Geometría y hover del anillo, aspecto de las referencias
  3. `OutputWriter` + tests
  4. `ImageConverter` (JPG/PNG/PDF)
  5. `MediaProbe` + `AudioConverter` + tests
  6. Cola y progreso
  7. WebP
  8. Anillo de Acciones (Copy, Copy Path, AirDrop, Move, Float)
  9. Anillo de Herramientas (`AudioTools`/`ImageTools` + tests)
  10. Menú y login item
  11. Scripts de build y DMG
- Commits pequeños por paso.
- Ante una API dudosa: **verificar antes de usar**. Nada de inventar símbolos.
- Licencia: el build de ffmpeg es GPL. Válido para uso personal; si se distribuye, incluir aviso y enlace a fuentes en `Resources/LICENSES/`.
