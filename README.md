# 🔄 ConvertBRUH

> Convierte, comparte y procesa archivos sin soltarlos.

ConvertBRUH es una aplicación ligera para la barra de menú de macOS que muestra un anillo de opciones alrededor del cursor mientras arrastras un archivo. Suéltalo sobre una porción y listo: la copia convertida aparece junto al original. Todo es local y el original nunca se toca.

[![Download DMG](https://img.shields.io/github/v/release/pablo96sancho/ConvertBRUH?label=Descargar%20DMG&color=007AFF&logo=apple)](https://github.com/pablo96sancho/ConvertBRUH/releases/latest)

---

## 🚀 Características

- ⇧ **Shift — Convertir:** MP3 · WAV · M4A · FLAC · AIFF para audio y vídeo, JPG · PNG · WEBP · PDF para imágenes
- ⌥ **Option — Acciones:** AirDrop, Float (miniatura flotante para arrastrar a otra app), Copy, Move y Copy Path
- ⌃ **Control — Herramientas:** Normalize (−14 LUFS), Compress, Channels (mono/estéreo) y Metadata (borrar tags, EXIF y GPS)
- 🎧 Calidad cuidada: conserva bit depth, sample rate, tags y carátula
- 📦 Lotes de varios archivos con progreso en el centro del anillo
- 🔒 Nunca sobrescribe nada: `beat.mp3`, `beat (1).mp3`…
- 💻 Nativa, ligera y sin Dock; funciona desde la barra de menú

---

## 📸 Vista previa

![ConvertBRUH Preview](cover.jpg)

---

## 📦 Instalación

1. Descarga la última versión desde [GitHub Releases](https://github.com/pablo96sancho/ConvertBRUH/releases/latest).
2. Abre el archivo `ConvertBRUH-Installer.dmg`.
3. Arrastra **ConvertBRUH.app** a la carpeta **Aplicaciones**.
4. La primera vez, haz **clic derecho → Abrir** (la app no está notarizada por Apple).
5. Ejecuta la app desde la barra de menú.

---

## 🧪 Cómo funciona

1. Empieza a arrastrar uno o varios archivos desde Finder, el Escritorio o Ableton.
2. Mientras arrastras, mantén **Shift**, **Option** o **Control**: aparece el anillo.
3. Suelta sobre una porción. Soltar en el centro cancela.
4. Al terminar, el resultado queda seleccionado en Finder.

Puedes cambiar de tecla a mitad del arrastre y el anillo cambia con ella.

---

## 🔒 Permisos

ConvertBRUH **no necesita permiso de Accesibilidad**. macOS puede pedirte acceso a carpetas como **Escritorio**, **Documentos** o **Descargas** la primera vez que guarde un archivo en ellas.

Si una carpeta no admite escritura (un DMG montado, un disco de solo lectura…), el resultado se guarda en **Descargas**.

---

## 🛠️ Desarrollo

### Requisitos

- macOS 13 o superior, Apple Silicon
- Xcode 15+ (Xcode 26+ para compilar el icono de Icon Composer)
- Swift 5.9+

### Compilar y ejecutar

```bash
chmod +x build_and_run.sh
./build_and_run.sh
```

La primera vez descarga los binarios estáticos de `ffmpeg` y `ffprobe` (`scripts/fetch-ffmpeg.sh`). La app se instala en `/Applications` y se abre.

### Tests

```bash
swift test
```

### Generar el instalador

```bash
./create_dmg.sh
```

Esto crea `ConvertBRUH-Installer.dmg` localmente. En GitHub, el instalador se publica como archivo adjunto de cada Release.

---

## 📄 Licencia

ConvertBRUH incluye [FFmpeg](https://ffmpeg.org) (GPL v3) como binario independiente. Ver [`Resources/LICENSES`](Resources/LICENSES/FFmpeg.txt).
