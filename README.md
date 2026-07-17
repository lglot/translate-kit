# TranslateKit

<p align="center">
  <img src="Resources/icon.png" width="80">
</p>

**Instant translation in any macOS app, in both directions.** Type in your language in any text field, press a hotkey, and the text is replaced with the translation in place. No popup, no copy-paste.

[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

macOS translates selected text only in native apps, and inline translation only in Safari. TranslateKit works everywhere: Slack, Chrome, VS Code, terminals, any text field.

## How it works

You configure a **language pair** (default Italian and English). TranslateKit detects which of the two languages the text is in and translates it to the other one. No direction to pick, ever.

- **⌃⌘R — Translate & replace.** Cursor in any text field: the whole field (or just your selection) is translated and replaced in place. Press again to undo. Write your email in Italian, press the hotkey, send it in English.
- **⌃⌘T — Translate & read.** Select text anywhere: the translation appears in a floating panel near the cursor, with a language switcher and full scrollable text.
- **Right-click → Services** also works: "Translate with TranslateKit" (popup) and "Translate and Replace with TranslateKit" (replaces the selection in place).

Both hotkeys are configurable in Settings.

## Translation engines

| Engine | Cost | Privacy | Setup |
|--------|------|---------|-------|
| **Apple (On-Device)** — default | Free | **Text never leaves your Mac** | None (language packs download once) |
| DeepL | 500k chars/mo free | Text sent to DeepL | [Get API key](https://www.deepl.com/pro-api) |
| Google Cloud | Paid | Text sent to Google | [Get API key](https://console.cloud.google.com/apis/credentials) |

API keys are stored in the macOS Keychain.

## Installation

Requires macOS 15+.

### Homebrew

```bash
brew install --cask --no-quarantine lglot/tap/translatekit
```

`--no-quarantine` is needed because releases are not yet notarized (no Apple Developer ID). If you skip it, right-click the app and choose Open the first time.

### Build from source

```bash
git clone https://github.com/lglot/translate-kit.git
cd translate-kit
make install
make refresh-services
```

### First run

1. Grant the **Accessibility permission** when prompted (System Settings → Privacy & Security → Accessibility). It is required to read the selection and replace text in other apps.
2. Pick your language pair in Settings if it is not Italian ⇄ English.
3. With the Apple engine, download the language pack from Settings → Languages if prompted.

## Under the hood

- Native Swift (SwiftUI + AppKit), one dependency ([KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)).
- Replace uses the **Accessibility API** (`AXUIElement`) where the target app supports it, and falls back to synthetic keyboard events (Cmd-A/C/V with clipboard save and restore) in apps with incomplete AX trees (Electron, Chromium).
- Language detection is local (`NLLanguageRecognizer`, constrained to your pair).
- Secure input fields (passwords) are always left alone.
- The "Translate and Replace" Service is synchronous: macOS swaps the selection with the translation the service leaves on the pasteboard.

## Project structure

```
Sources/
├── TranslateKitApp.swift             # Entry point, AppDelegate, menu bar, hotkey flows
├── ServiceProvider.swift             # macOS Services (popup + synchronous replace)
├── Backends/                         # TranslationBackend protocol + Apple, DeepL, Google Cloud
├── Models/                           # Language, LanguagePair (flip logic), TranslationResult
├── Services/
│   ├── AppleTranslationProvider.swift  # Headless TranslationSession host
│   ├── ReplaceEngine.swift             # AX + CGEvent capture/replace, undo
│   ├── TranslationCoordinator.swift    # Pair detection → backend dispatch
│   ├── BackendManager.swift
│   └── PreferencesManager.swift
├── Utilities/                        # Keychain, hotkey names
└── Views/                            # Floating panel, Settings, Onboarding
```

## Build commands

```bash
make build              # Compile (debug)
make test               # Run tests
make install            # Build + install to /Applications
make release            # Universal binary bundle + zip
make refresh-services   # Refresh macOS Services cache
make uninstall          # Remove from /Applications
```

## License

MIT — see [LICENSE](LICENSE).
