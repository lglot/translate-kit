# TranslateKit

<p align="center">
  <img src="Resources/icon.png" width="80">
</p>

A lightweight macOS menu bar app that adds **"Translate" to your right-click context menu** for any selected text in any app.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- **System-wide Service** — right-click any selected text → Services → "Translate with TranslateKit"
- **Floating panel** near cursor with translation result
- **4 translation engines**:
  - 🌐 **Google Translate** — free, no API key needed
  - 🍎 **Apple Translation** — on-device, private, macOS 15+
  - 🔵 **DeepL** — free API key (500k chars/month)
  - 🟢 **Google Cloud** — requires API key
- **Menu bar icon** for quick settings
- **Global hotkey** `⌘⇧T` to translate clipboard
- **Auto-detect** source language
- **25+ target languages** with flag emojis
- API keys stored in **macOS Keychain**

## Installation

### Homebrew (recommended)

```bash
brew install --cask lglot/tap/translatekit
```

### Build from source

```bash
git clone https://github.com/lglot/translate-kit.git
cd translate-kit
make install
```

Then **log out and back in** (or run `make refresh-services`) for the Service to appear.

## Usage

1. **Select text** in any app (Safari, Xcode, Notes, Terminal...)
2. **Right-click** → Services → **"Translate with TranslateKit"**
3. A floating panel appears with the translation
4. Click outside or press **Escape** to dismiss

### Menu Bar

Click the 🌐 icon to:
- Switch translation engine
- Change target language
- Open Settings

### Keyboard

Press **`⌘⇧T`** to translate current clipboard content.

## Translation Engines

| Engine | Cost | Quality | Privacy | Setup |
|--------|------|---------|---------|-------|
| Google Translate | Free | Good | Text sent to Google | Default |
| Apple (On-Device) | Free | Good | **Private** (on-device) | macOS 15+ |
| DeepL | 500k chars/mo free | Excellent | Text sent to DeepL | [Get API key](https://www.deepl.com/pro-api) |
| Google Cloud | Paid | Excellent | Text sent to Google | [Get API key](https://console.cloud.google.com/apis/credentials) |

## How It Works

```
Any App → Right-click → Services → TranslateKit
                                ↓
                    ServiceProvider receives text
                                ↓
                    Floating NSPanel near cursor
                                ↓
                    Translation backend processes
                                ↓
                    Result: Copy or dismiss
```

TranslateKit registers as a macOS **Service** via `NSServices` in `Info.plist`. When triggered, the text is passed via `NSPasteboard` (Mach port IPC), translated by the selected backend, and displayed in a floating `NSPanel`.

## Project Structure

```
Sources/
├── TranslateKitApp.swift         # Entry point, AppDelegate, menu bar
├── ServiceProvider.swift         # NSServices handler
├── Backends/
│   ├── TranslationBackend.swift  # Protocol
│   ├── GoogleWebBackend.swift    # Free (default)
│   ├── AppleBackend.swift        # macOS 15+ on-device
│   ├── DeepLBackend.swift        # DeepL API
│   └── GoogleCloudBackend.swift  # Google Cloud API
├── Models/
│   ├── Language.swift            # 25+ languages with flags
│   └── TranslationResult.swift   # Result DTO
├── Services/
│   ├── BackendManager.swift      # Engine manager
│   └── PreferencesManager.swift  # User settings
├── Utilities/
│   └── KeychainHelper.swift      # Secure API key storage
└── Views/
    ├── FloatingPanel.swift       # NSPanel floating window
    ├── TranslationView.swift     # Main translation UI
    ├── SettingsView.swift        # Preferences window
    └── MenuBarView.swift         # Menu bar dropdown
```

## Build Commands

```bash
make build              # Compile
make install            # Build + install to /Applications
make icon               # Regenerate app icon
make refresh-services   # Refresh macOS Services cache
make uninstall          # Remove from /Applications
```

## Contributing

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/amazing`)
3. Commit (`git commit -m 'feat: amazing feature'`)
4. Push (`git push origin feature/amazing`)
5. Open a Pull Request

## License

MIT — see [LICENSE](LICENSE).
