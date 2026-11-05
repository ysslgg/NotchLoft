<div align="center">

**English · [Français](README.fr.md)**

<img src="Resources/AppIcon-1024.png" width="128" alt="NotchLoft icon">

# NotchLoft

**The toolbox hidden in your MacBook's notch.**

Now playing, clipboard history, a screenshot shelf, a file tray, a file converter, battery and system stats: hover the notch and everything is there.

[![Download NotchLoft](https://img.shields.io/badge/%E2%AC%87%EF%B8%8E%20Download-NotchLoft.dmg-8A2BE2?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/ysslgg/NotchLoft/releases/latest/download/NotchLoft.dmg)

![Latest version](https://img.shields.io/github/v/release/ysslgg/NotchLoft?color=8A2BE2&label=version)
![Downloads](https://img.shields.io/github/downloads/ysslgg/NotchLoft/total?color=ec4899&label=downloads)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-444?logo=apple&logoColor=white)
![Apple Silicon and Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-444)

<br>

<img src="docs/hover.png" width="460" alt="Now playing, when hovering the notch">

<sub>Music</sub>

<img src="docs/shelf.png" width="460" alt="The shelf: your latest screenshots hanging on a clothesline">

<sub>Screenshot shelf</sub>

<img src="docs/clipboard.png" width="400" alt="Clipboard history">

<sub>Clipboard</sub>

<img src="docs/files.png" width="460" alt="The file tray: files hanging on the clothesline">

<sub>File tray</sub>

<img src="docs/converter.png" width="460" alt="The file converter: pick a format, with a description on hover">

<sub>File converter</sub>

<img src="docs/system.png" width="420" alt="Battery and system: battery level, CPU, memory and disk">

<sub>Battery & system</sub>

<br>

<img src="docs/compact.png" width="460" alt="The idle notch: artwork on the left, visualizer on the right">

<sub>Idle</sub>

</div>

## Features

### 🎵 Music
- Reads the system "Now Playing": Apple Music, Spotify, your browser…
- **Idle**, the notch widens just a little: artwork on the left (with a progress ring), animated visualizer on the right (the bars follow the sound, bass on the left and treble on the right), a pause symbol when paused. Nothing shows when nothing is playing.
- **On hover**: artwork, title and artist (scrolling when long), a progress bar you can click or drag, elapsed and remaining time, previous / play-pause / next. Click the source app's icon to open Spotify, Music…
- Accent colors taken from the artwork, or a fixed color of your choice.

### 📋 Clipboard
- History of copied text (30 items); one click puts an item back on the clipboard.
- Pin the important items: they stay, even after a restart.
- Passwords copied from password managers (1Password and others) are never recorded.

### 🧷 Screenshot shelf
- Your latest captures (up to 30) hang on a clothesline with clothespins. Scroll left or right to see the others.
- **Everything goes in**: screenshots, **screen recordings** (with their duration), and captures copied to the clipboard (⌃⇧⌘3 / ⌃⇧⌘4).
- **Animation**: each new capture flies to the notch, which opens for a moment to hang it up.
- Click to open, **drag and drop** into any app, a **cross** on hover that moves the capture to the Trash (so it disappears from your Desktop too, and you can still recover it from the Trash), right-click to copy, show in Finder, or remove it from the shelf only (the file stays untouched).

### 📥 File tray
- Drag a file or folder onto the notch: it opens by itself and the item hangs on the clothesline.
- Take it back later by dragging it into any app. Nothing is copied or moved: these are shortcuts to your files.
- Click to open, cross to remove, right-click to show in Finder or copy its path.

### 🔄 File converter
- Drop a file (or several) on the notch, pick the format you want, done: the result lands next to the original, never overwriting anything.
- **Hover a format to see what it is** (quality, size, compatibility) before you choose.
- **Images** (PNG, JPEG, HEIC, TIFF, GIF, BMP, JPEG 2000, AVIF, WebP*, ICO, ICNS…) → other images, PDF, or text (OCR). Camera RAW and PSD files can be read too.
- **PDF** → one image per page, text, or OCR for scans; several PDFs can be merged.
- **Audio** (WAV, AIFF, MP3, M4A, FLAC, OGG…) → M4A, lossless M4A, WAV, AIFF, CAF, FLAC, AAC (+ MP3, OPUS, OGG, WMA, AC3 with ffmpeg).
- **Video** (MP4, MOV, MKV, AVI, WebM…) → MP4 1080p / 720p / 480p, HEVC, MOV, M4V, animated GIF, a frame as PNG/JPEG, or just the sound (+ MKV, AVI, WebM, WMV, FLV, MPEG-2 with ffmpeg). An animated GIF can become an MP4.
- **Documents** (DOCX, DOC, ODT, RTF, HTML, TXT, Markdown…) → each other, plus PDF; Markdown is rendered to HTML.
- **Data** (JSON, plist, CSV, TSV) → each other, plus YAML, Markdown or HTML tables.
- **Archives and folders** → ZIP, TAR, TAR.GZ, TAR.BZ2, or extract; Base64 encode/decode for any file.
- When you drag a file onto the notch, two zones appear: **hang it in the tray** or **convert it**. Everything runs on your Mac, nothing is uploaded.
- <sub>*Extra formats (MP3, OGG, OPUS, WebM, MKV, WebP output…) appear automatically if [ffmpeg](https://ffmpeg.org) is installed (`brew install ffmpeg`).</sub>

### 🔋 Battery & system
- Battery level, charging state, time remaining, health and cycles, plus CPU, memory, **memory pressure** (normal / elevated / critical, like Activity Monitor) and disk.
- **You choose what is shown large**: click a gauge to bring it forward (or use the ♪ menu). The CPU adds a live graph.

### And also
- **Tabs** in the notch's wings to switch between tools.
- **English or French**: the interface is in English by default; switch to French from the ♪ menu → Language.
- **Customizable** from the menu bar icon: page on open (a fixed page or the last used), enable or disable each tool, visualizer, progress ring, blurred background, haptic feedback, accent color, idle width, hide after a pause, launch at login, update checks.
- **Discreet**: no Dock icon, and the idle notch hides in full-screen apps (it still opens when you hover the notch). Adjustable in the ♪ menu.
- **For every Mac**: on a Mac without a notch, a simulated notch takes over.

## Installation

1. Download **NotchLoft.dmg** with the button above.
2. Open the DMG and drag **NotchLoft** into **Applications**.
3. On first launch, macOS shows a warning because the app is not notarized. Open **System Settings → Privacy & Security**, scroll down to NotchLoft and click **Open Anyway**.
4. For the shelf, allow access to the screenshots folder (Desktop by default) when macOS asks.

## Limitations

- The clipboard keeps text only, not images or files.
- The shelf can't see captures sent straight to an app (Mail, Messages…): they exist neither as a file nor on the clipboard.
- The visualizer follows the Mac's sound when you allow it (macOS 14.2 or later); without permission it stays a decorative animation. It can't see DRM-protected audio.
- The app is not notarized by Apple, hence the warning on first launch.
- Playback info depends on what the app reports to the system: some players send neither artwork nor duration.
- Personal use only, see the [license](LICENSE).
