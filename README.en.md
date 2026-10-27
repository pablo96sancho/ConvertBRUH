<div align="center">

<img src="ICON%20APP/ConvertBRUH%20ICON%20Exports/ConvertBRUH%20ICON-iOS-Default-1024@1x.png" width="128" alt="ConvertBRUH icon" />

# ConvertBRUH

**Convert, share and process files without letting go of them.**

[![Download for macOS](https://img.shields.io/badge/Download_for_macOS-0071E3?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/pablo96sancho/ConvertBRUH/releases/latest/download/ConvertBRUH-Installer.dmg)

![Version](https://img.shields.io/github/v/release/pablo96sancho/ConvertBRUH?style=flat-square&label=version&color=000000)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?style=flat-square&logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1%2B-000000?style=flat-square)
![GPL-3.0 License](https://img.shields.io/badge/license-GPL--3.0-000000?style=flat-square)

[🇪🇸 Versión en español](./README.md)

</div>

<br />

<p align="center">
  <img src="cover.jpg" width="720" alt="ConvertBRUH's three rings: Convert with Shift, Actions with Option and Tools with Control" />
</p>

ConvertBRUH is a menu bar app that shows a ring of options around the cursor while you
drag a file. Drop it on a slice and you're done: the result appears next to the original.
Everything runs locally and the original is never touched. The interface is in Spanish.

## How it works

1. Start dragging one or more files from the Finder, the Desktop or Ableton.
2. While dragging, hold **Shift**, **Option** or **Control**: the ring appears.
3. Drop the file on a slice. Dropping it in the center cancels.
4. When it's done, the result is selected in the Finder.

You can switch keys mid-drag and the ring changes with it.

## Features

| Key | Ring | What you can do |
|---|---|---|
| ⇧ **Shift** | **Convert** | Audio to MP3, WAV, M4A, FLAC or AIFF · images to JPG, PNG, WEBP or PDF · video to MP4, MOV or GIF, or extract the audio · PDF to TXT, DOCX, JPG or PNG |
| ⌥ **Option** | **Actions** | AirDrop · Float (a floating thumbnail you can drag into another app) · Copy · Move · Copy Path |
| ⌃ **Control** | **Tools** | Audio: Normalize (−14 LUFS), Compress, Channels and Metadata · Image: Compress, **AI Upscale ×4** and Metadata · Video: Compress and Mute · PDF: Metadata |

- 🎧 **Quality first:** keeps bit depth, sample rate, tags and cover art. Video is copied without re-encoding whenever possible.
- 🧠 **Local AI upscaling:** enlarges images ×4 with Real-ESRGAN on the Mac's Neural Engine, with no internet or accounts.
- 📦 **Batches:** several files at once, with progress shown in the center of the ring.
- 🔒 **Never overwrites anything:** `beat.mp3`, `beat (1).mp3`…
- 💻 **Native and lightweight:** Swift with SwiftUI and AppKit, no Dock icon.

## Installation

1. [Download the installer](https://github.com/pablo96sancho/ConvertBRUH/releases/latest/download/ConvertBRUH-Installer.dmg).
2. Open it and drag **ConvertBRUH.app** to **Applications**.
3. Launch it. It will appear in the menu bar.

### First launch

The app isn't signed with an Apple Developer account, so macOS blocks it the first time.
To open it:

1. Try to open ConvertBRUH and close the warning (don't move it to the Trash).
2. Go to **System Settings → Privacy & Security**.
3. Under **Security**, click **Open Anyway** next to the message about ConvertBRUH.
4. Confirm with your password or Touch ID. You only need to do this once.

<details>
<summary>Alternative using Terminal</summary>

```bash
xattr -dr com.apple.quarantine /Applications/ConvertBRUH.app
```

</details>

### Permissions

ConvertBRUH **doesn't need Accessibility permission**. macOS may ask for access to folders
such as **Desktop**, **Documents** or **Downloads** the first time it saves a file there.
If a folder isn't writable (a mounted DMG, a read-only disk…), the result is saved to
**Downloads**.

## Development

Requirements: macOS 13 or later on Apple Silicon, Xcode 15+ (Xcode 26+ to build the Icon
Composer icon) and Swift 5.9+.

```bash
./build_and_run.sh   # downloads ffmpeg the first time, builds, installs to /Applications and opens
swift test           # tests
./create_dmg.sh      # creates ConvertBRUH-Installer.dmg
```

Every GitHub Release publishes the DMG automatically with GitHub Actions.

## License

[GPL-3.0](LICENSE) © Pablo Sancho

ConvertBRUH bundles [FFmpeg](https://ffmpeg.org) (GPL v3) as a separate binary and the
[Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) model (BSD-3-Clause). Their notices
are in [`Resources/LICENSES`](Resources/LICENSES).
