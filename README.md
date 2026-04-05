<div align="center">

<img src="build/appicon.png" width="96" alt="ArchInit logo">

# ArchInit — Setup Wizard

**A beautiful, universal Arch Linux setup wizard.**  
Simple enough for a 60-year-old. Fast enough for a developer.

[![Release](https://img.shields.io/github/v/release/KiruhiHub/SetupWizard?style=flat-square&color=7c6af8)](https://github.com/KiruhiHub/SetupWizard/releases)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Built with Wails](https://img.shields.io/badge/built%20with-Wails%20v2-blueviolet?style=flat-square)](https://wails.io)

</div>

---

## ✨ Features

- **3-step onboarding** — Profile → Desktop style → Cloud sync
- **Icon-first UI** — No technical jargon, universal symbols
- **QR-based cloud auth** — Connect Google Drive, iCloud, OneDrive via rclone
- **Live log streaming** — Watch installation progress in real time
- **Dark UI** — Modern, minimal, production-grade design
- **Wails v2** — Native desktop app, Go backend + Vite frontend

## 📸 Screenshots

| Step 1 — Profile | Step 2 — Desktop | Step 3 — Cloud |
|:---:|:---:|:---:|
| Choose your usage profile | Pick your desktop style | Connect cloud storage |

## 🚀 Quick Start

### Prerequisites

- [Go 1.21+](https://go.dev/dl/)
- [Node.js 18+](https://nodejs.org/)
- [Wails v2](https://wails.io/docs/gettingstarted/installation)
- [rclone](https://rclone.org/install/) *(for cloud sync)*

### Development

```bash
git clone https://github.com/KiruhiHub/SetupWizard.git
cd SetupWizard
wails dev
```

### Build

```bash
wails build
```

Binary will be at `build/bin/SetupWizard`.

## 🏗️ Project Structure

```
SetupWizard/
├── main.go              # Wails entry point
├── app.go               # Go backend (rclone, setup runner)
├── scripts/
│   └── setup.sh         # Installation script
├── frontend/
│   ├── index.html       # Step 1 — Profile
│   ├── page1.html       # Step 2 — Desktop style
│   ├── page2.html       # Step 3 — Cloud sync
│   └── src/
│       ├── main.js      # Frontend logic
│       └── css/style.css
└── wails.json
```

## 🔧 How It Works

1. User selects a **profile** (Daily / Developer / Custom)
2. User picks a **desktop style** (Windows / macOS / KDE)
3. User optionally connects **cloud storage** via QR code (rclone OAuth)
4. Backend runs `scripts/setup.sh` with selected options
5. Live logs stream to frontend via Wails events

## 📦 Profiles

| Profile | Installs |
|---------|----------|
| 🏠 Daily | Browser, Spotify, LibreOffice, VLC |
| 💻 Developer | VS Code, Docker, Git, zsh, btop |
| 🎛️ Custom | You choose |

## 🤝 Contributing

PRs welcome. Open an issue first for major changes.

## 📄 License

MIT © [KiruhiHub](https://github.com/KiruhiHub)
