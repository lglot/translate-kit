# TranslateKit

A lightweight macOS menu bar app that adds **"Translate" to your right-click context menu** for any selected text in any app.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- **System-wide Service** — right-click any selected text in any app, go to Services, pick "Translate with TranslateKit"
- **Floating panel** appears near your cursor with the translation
- **Multiple translation engines**:
  - 🌐 **Google Translate** — free, no API key needed (default)
  - 🔵 **DeepL** — requires free API key (500k chars/month)
  - 🟢 **Google Cloud** — requires API key
  - 🍎 **Apple Translation** — on-device, macOS 15+ only
- **Menu bar icon** for quick access to settings and language switching
- **Global hotkey** `⌘⇧T` to translate clipboard content
- **Auto-detect** source language
- **Copy** or **Replace** translated text directly
- **25+ target languages** with flag emojis
- API keys stored securely in **macOS Keychain**

## Installation

### Build from source

```bash
git clone https://github.com/yourusername/TranslateKit.git
cd TranslateKit
make install
```

Then **log out and log back in** (or reboot) for the Service to appear in context menus.

### Quick refresh (no logout)

```bash
make refresh-services
```

## Usage

1. **Select text** in any app (Safari, Xcode, Notes, etc.)
2. **Right-click** → Services → **"Translate with TranslateKit"**
3. A floating panel appears with the translation

### Menu Bar

Click the 🌐 icon in your menu bar to:
- Switch translation engine
- Change target language
- Open Settings

### Keyboard Shortcut

Press `⌘⇧T` to translate the current clipboard content.

## Configuration

Open **Settings** from the menu bar icon to configure:

| Setting | Description |
|---------|-------------|
| Target language | Default language to translate to (default: Italian) |
| Translation engine | Google Translate, DeepL, Google Cloud, or Apple |
| Auto-detect source | Automatically detect the source language |
| Launch at login | Start TranslateKit when you log in |
| Show menu bar icon | Toggle the menu bar icon visibility |

### API Keys

API keys are stored in your **macOS Keychain** (never in plain text):

- **DeepL**: Get a free key at [deepl.com/pro-api](https://www.deepl.com/pro-api) (500k chars/month free)
- **Google Cloud**: Get a key at [console.cloud.google.com](https://console.cloud.google.com/apis/credentials)

## How It Works

TranslateKit uses the **macOS Services API** (`NSServices`) to register as a system-wide text service:

```
User selects text → Right-click → Services → TranslateKit
        ↓
  NSPasteboard (Mach port)
        ↓
  ServiceProvider receives text
        ↓
  Floating NSPanel appears near cursor
        ↓
  Translation backend processes text
        ↓
  Result displayed with Copy/Replace actions
```

## Architecture

```
Sources/
├── TranslateKitApp.swift         # Entry point, AppDelegate, menu bar
├── ServiceProvider.swift         # NSServices handler
├── Backends/
│   ├── TranslationBackend.swift  # Protocol
│   ├── GoogleWebBackend.swift    # Free Google Translate
│   ├── DeepLBackend.swift        # DeepL API
│   ├── GoogleCloudBackend.swift  # Google Cloud Translation
│   └── AppleBackend.swift        # Apple Translation (macOS 15+)
├── Models/
│   ├── Language.swift            # Language enum with flags
│   └── TranslationResult.swift   # Result DTO
├── Services/
│   ├── BackendManager.swift      # Manages active backend
│   └── PreferencesManager.swift  # User preferences
├── Utilities/
│   └── KeychainHelper.swift      # Secure API key storage
└── Views/
    ├── FloatingPanel.swift       # NSPanel (floating window)
    ├── TranslationView.swift     # Main translation UI
    ├── TranslationViewModel.swift # View state management
    ├── MenuBarView.swift         # Menu bar dropdown
    └── SettingsView.swift        # Preferences window
```

## Building

### Requirements

- macOS 13+ (Ventura)
- Swift 5.9+
- Xcode 15+ (command line tools)

### Commands

```bash
# Build only
make build

# Build and install to /Applications
make install

# Refresh Services cache (no logout needed)
make refresh-services

# Run directly
make run

# Uninstall
make uninstall
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- Google Translate's unofficial API for free translations
- DeepL for their excellent translation quality
- Apple's Translation framework for on-device privacy-first translation
