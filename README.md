# TranslateKit

<p align="center">
  <img src="Resources/icon.png" width="80">
</p>

**Instant translation in any macOS app, with a native app and the `tkit` CLI.**

[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

TranslateKit can replace selected text in place, show a floating translation panel, expose macOS Services, or translate from a terminal. The app and CLI share the same provider and language configuration.

## App workflow

Configure a language pair, Italian and English by default. With no explicit target, TranslateKit detects which member of the pair the text uses and translates to the other one.

- **Control-Command-R: Translate and replace.** Translate the current selection or editable field in place.
- **Control-Command-T: Translate and read.** Show the result in a floating panel near the cursor.
- **Services menu.** Use `Translate with TranslateKit` or `Translate and Replace with TranslateKit` from compatible macOS apps.

Both hotkeys are configurable in Settings. Accessibility permission is required for global capture and in-place replacement.

## Providers

| Provider | Authentication | Cost boundary | Privacy |
| --- | --- | --- | --- |
| Apple Translation | None | Included with macOS | On-device. Text stays on the Mac. |
| DeepL | API key | Free, trial, and paid API plans depend on account eligibility. See [current DeepL API plans](https://support.deepl.com/hc/en-us/articles/360021200939-DeepL-API-plans). | Text is sent to DeepL. |
| Google Cloud Translation | API key or `gcloud` session | The current Basic pricing includes a monthly credit for the first 500,000 characters. See [Google pricing](https://cloud.google.com/translate/pricing). | Text is sent to Google Cloud. |
| Azure Translator | API key or Azure CLI session | Azure currently lists an F0 free tier, subject to resource and region availability. See [Azure pricing](https://azure.microsoft.com/pricing/details/cognitive-services/translator/). | Text is sent to Azure. |
| Amazon Translate | AWS native credential chain or Keychain static credentials | Eligible accounts can use the Amazon Translate free tier, then pay per character. See [AWS pricing](https://aws.amazon.com/translate/pricing/). | Text is sent to AWS. |
| LibreTranslate-compatible | Optional API key | Self-hosting uses free software but consumes your hardware. Managed instances can charge. | Text is sent only to the configured server. |

LibreTranslate is powered by Argos Translate, not an LLM. TranslateKit also accepts compatible servers such as LTEngine, whose internal model can differ. Pricing and free-tier rules can change, so verify the linked provider page before enabling billing.

There is no automatic provider fallback. If the selected provider fails or lacks credentials, TranslateKit returns that error instead of sending text to another service.

## Languages

The Settings catalog is built from the Foundation ISO language catalog instead of a fixed Italian-English list. The CLI accepts validated BCP-47 codes such as `pt-BR`. Actual language and pair support still depends on the selected provider and, for Apple, on downloaded local models.

## CLI

The executable is named `tkit`. A source checkout can run it with `swift run tkit`. A packaged app contains it at:

```text
/Applications/TranslateKit.app/Contents/MacOS/tkit
```

Examples:

```bash
# Create the shared configuration file.
tkit config init

# Translate positional text using the configured pair and provider.
tkit translate "Ciao a tutti"

# Use explicit languages and provider.
tkit translate "Bom dia" --from pt-BR --to en --provider deepl

# Read text from stdin and emit stable JSON.
printf 'Hello' | tkit translate --to it --json

# Inspect providers without making a paid translation request.
tkit providers list
tkit providers list --json

# Inspect and edit non-secret configuration.
tkit config path
tkit config show
tkit config get translation.provider
tkit config set translation.provider libretranslate

# Discover credential sources without printing secret values.
tkit config discover
tkit config discover aws --json

# Save or delete a provider key through a secure prompt or stdin.
tkit config set-key deepl
tkit config delete-key deepl
```

Use `--config PATH` on a concrete command to select an isolated configuration:

```bash
tkit config init --config /tmp/translate-kit.toml
tkit translate "Hello" --to it --config /tmp/translate-kit.toml
```

Plain translation writes only the translated text and one newline to stdout. Diagnostics go to stderr. Exit codes are `2` for usage, `3` for configuration or credentials, and `1` for provider or translation failures.

## Configuration

The default file is `~/.config/translate-kit/config.toml`. It is created with mode `0600`, written atomically, and shared by the app and CLI.

```toml
version = 1

[translation]
provider = "apple"
first_language = "it"
second_language = "en"

[providers.deepl]
plan = "free"

[providers.google_cloud]
auth = "auto"

[providers.azure]
auth = "auto"
endpoint = "https://api.cognitive.microsofttranslator.com"
region = ""

[providers.aws]
auth = "profile"
profile = ""
region = ""

[providers.libretranslate]
endpoint = "http://localhost:5000"
```

TOML never contains API keys, bearer tokens, AWS access keys, secret keys, or session tokens. Unknown keys and invalid endpoints are rejected. Remote LibreTranslate endpoints require HTTPS; plain HTTP is accepted only for loopback hosts.

Azure endpoints are restricted to Microsoft Translator global or regional hosts and official `cognitiveservices` custom domains. Entra CLI authentication requires a resource-specific custom domain in the public Azure cloud. Sovereign Azure endpoints remain available with API-key authentication.

GUI-only state such as onboarding, launch at login, and menu-bar visibility remains in `UserDefaults`. On first launch, legacy language, provider, and DeepL plan values are migrated to TOML only when the file is missing.

## Credentials

TranslateKit-owned secrets use macOS Keychain service `com.translatekit.app`. Existing `deepl_api_key` and `google_cloud_api_key` accounts remain compatible.

Credential discovery is allowlisted and read-only:

- DeepL: TranslateKit Keychain, `DEEPL_AUTH_KEY`, and the known DeepL keyring item.
- Google: TranslateKit Keychain, API-key environment variables, or an existing `gcloud` application-default session.
- Azure: TranslateKit Keychain, `AZURE_TRANSLATOR_KEY`, or an existing Azure CLI session. Discovery checks local Azure CLI session metadata without minting a token; a short-lived token is requested only for translation.
- AWS: standard environment and SDK credential chain, profile names from standard AWS files, SSO, login, role, and `credential_process`. Profile names and regions can be stored in TOML; secret values cannot.
- LibreTranslate: TranslateKit Keychain or `LIBRETRANSLATE_API_KEY`.

Short-lived native tokens are used in place and are never copied to TranslateKit's Keychain. `config set-key` accepts a secret from a hidden terminal prompt or stdin, never from a command-line argument.

## Installation

Requires macOS 15 or later.

### Homebrew app

```bash
brew install --cask --no-quarantine lglot/tap/translatekit
```

`--no-quarantine` is currently needed because releases are not notarized. The external Homebrew metadata must be updated separately before it can expose the bundled `tkit` executable directly on `PATH`.

### Build from source

```bash
git clone https://github.com/lglot/translate-kit.git
cd translate-kit
make install
make refresh-services
```

The install and release bundles include both `TranslateKit` and the signed auxiliary `tkit` executable.
`make install` and `make release` require the project's stable `TranslateKit Dev` code-signing identity in the login Keychain so macOS can preserve Accessibility trust across rebuilds. Plain SwiftPM builds and `swift run tkit` do not require that identity.

## First run

1. Grant Accessibility permission in System Settings, Privacy and Security, Accessibility.
2. Pick a language pair and provider in Settings.
3. For Apple Translation, download the required language pack when prompted.
4. For a cloud provider, configure native credentials or save an API key in Keychain.

## Architecture

```text
TranslateKitCore
  Language, configuration, Keychain abstraction, provider registry,
  REST backends, AWS backend, and translation service

TranslateKitApple -> TranslateKitCore
  Apple Translation adapter and hidden TranslationSession host

TranslateKit -> TranslateKitCore + TranslateKitApple
  Menu-bar app, Settings, hotkeys, Services, Accessibility, and panels

tkit -> TranslateKitCore + TranslateKitApple
  Argument parsing, stdin/stdout, configuration commands, and exit codes
```

The code uses SwiftUI, AppKit, Foundation Translation, Security, `KeyboardShortcuts`, `swift-argument-parser`, `swift-toml`, and the Amazon Translate product from AWS SDK for Swift.

## Build commands

```bash
make build              # Build app and CLI in debug mode
make test               # Run tests
make run                # Run the app executable
make run-cli            # Build and run tkit
make install            # Build, sign, and install the app bundle
make release            # Build a universal signed bundle and zip
make refresh-services   # Refresh the macOS Services cache
make uninstall          # Remove the installed app
```

Direct SwiftPM commands:

```bash
swift build --product TranslateKit
swift build --product tkit
swift test
swift run tkit --help
```

## License

MIT. See [LICENSE](LICENSE).
