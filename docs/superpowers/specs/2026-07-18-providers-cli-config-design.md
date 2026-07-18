# Translation providers, shared configuration, and `tkit` CLI

## Status

Approved for implementation on 2026-07-18. This design extends the existing API-key settings design with the full provider, configuration, credential-discovery, and CLI scope.

## Goals

- Support Apple Translation, DeepL, Google Cloud Translation, Azure Translator, Amazon Translate, and LibreTranslate-compatible servers, including LTEngine.
- Let the app translate any valid BCP-47 language code, subject to the selected provider's actual capabilities.
- Add an independent `tkit` executable for translation and configuration.
- Make a human-editable TOML file the shared source of truth for translation settings.
- Keep API keys and manually entered static AWS credentials out of TOML and in the macOS Keychain.
- Discover existing credentials and native cloud profiles without copying or exposing secrets.
- Preserve the existing menu-bar app, hotkeys, Services, Accessibility behavior, and Apple on-device default.

## Non-goals

- No automatic fallback from one translation provider to another. A fallback could leak text to an unexpected service.
- No browser-cookie extraction or broad Keychain scan.
- No shell-history, dotfile, or arbitrary `.env` scanning.
- No account creation, cloud-resource provisioning, or automatic provider login.
- No document translation or glossary management in this iteration.

## Package architecture

SwiftPM exposes four targets with one-way dependencies:

```text
TranslateKitCore
  models, language handling, configuration, credentials,
  provider registry, REST backends, AWS backend, translation service

TranslateKitApple -> TranslateKitCore
  Apple Translation adapter and invisible AppKit/SwiftUI session host

TranslateKit -> TranslateKitCore + TranslateKitApple
  menu-bar app, hotkeys, Services, Accessibility, settings, panels

tkit -> TranslateKitCore + TranslateKitApple
  command-line parsing, stdin/stdout, exit-code mapping
```

`TranslateKitCore` contains no menu-bar or Accessibility behavior. `TranslateKitApple` isolates the UI-host requirement imposed by `TranslationSession`. The Apple adapter initializes `NSApplication` and an invisible host window only when Apple is the selected CLI provider. Cloud-only CLI commands remain headless.

## Language model

`Language` changes from a closed enum to a validated, hashable BCP-47 value type. Existing conveniences such as `.italian`, `.english`, and `.auto` remain available so current app flows and tests stay readable.

- `Locale.LanguageCode.isoLanguageCodes` supplies the GUI catalog.
- `Locale` supplies localized display names.
- The value type accepts provider-specific or regional identifiers that are not in the GUI catalog, such as `pt-BR`.
- `auto` is valid only as a source.
- Backends validate or report unsupported pairs using their own response or capability API. The core does not pretend every provider supports every ISO language.
- Pair-based local detection remains constrained to the configured two languages.

## Configuration ownership

The default file is `~/.config/translate-kit/config.toml`. `tkit --config <path>` selects an alternative file for that invocation. The default schema is:

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

Rules:

- TOML contains only non-secret values.
- Unknown keys are rejected with a precise parse or validation error instead of being silently ignored.
- Writes are atomic and create the parent directory with user-only permissions.
- Existing files are not rewritten merely because they were read.
- CLI `config set` rewrites a canonical, deterministically ordered representation.
- A remote LibreTranslate endpoint must use HTTPS. Plain HTTP is accepted only for loopback hosts.
- `UserDefaults` retains GUI-only state such as onboarding, launch at login, menu-bar visibility, and hotkeys.

## Migration

On the first load when the TOML file does not exist:

1. Read the existing language pair, active backend, and DeepL plan from `UserDefaults`.
2. Validate them and create the TOML file atomically.
3. Preserve existing Keychain item names so saved DeepL and Google keys continue to work.
4. Mark migration complete in GUI-only preferences.

If TOML already exists, it wins and migration does not overwrite it. Invalid TOML is reported and preserved for manual repair.

## Provider registry

Each provider has a descriptor containing a stable ID, display name, privacy classification, credential requirements, and a backend factory. App and CLI enumerate the same registry.

| ID | Backend | Authentication | API |
| --- | --- | --- | --- |
| `apple` | Apple Translation | None | `TranslationSession` |
| `deepl` | DeepL | API key | REST v2, Free or Pro host |
| `google-cloud` | Google Cloud Translation | API key or native Google credentials | Translation Basic REST v2 |
| `azure` | Azure Translator | API key or Entra token | Text Translation REST v3.0 |
| `aws` | Amazon Translate | AWS credential chain or manual static credentials | AWS SDK `TranslateText` |
| `libretranslate` | LibreTranslate-compatible | Optional API key | `POST /translate` |

Provider selection is explicit: CLI `--provider`, then TOML default. Missing credentials or an unsupported language returns an error. There is no automatic provider fallback.

## Credential storage and discovery

TranslateKit-owned secrets use Keychain service `com.translatekit.app`.

| Provider | TranslateKit Keychain account | Additional read-only sources |
| --- | --- | --- |
| DeepL | `deepl_api_key` | `DEEPL_AUTH_KEY`; allowlisted `deepl` keyring item |
| Google | `google_cloud_api_key` | `GOOGLE_CLOUD_API_KEY`, `GOOGLE_API_KEY`; gcloud/ADC session |
| Azure | `azure_translator_api_key` | `AZURE_TRANSLATOR_KEY`; Azure CLI Entra session |
| AWS | optional `aws_access_key_id`, `aws_secret_access_key`, `aws_session_token` | standard AWS environment, profiles, SSO, login, role, and `credential_process` chain |
| LibreTranslate | `libretranslate_api_key` | `LIBRETRANSLATE_API_KEY` |

Credential behavior:

- A key explicitly stored in TranslateKit's Keychain wins for key-based providers.
- Environment variables are process-local fallback sources.
- Native short-lived Google, Azure, and AWS credentials are used in place and are never copied to TranslateKit's Keychain.
- AWS profile names are enumerated without reading or displaying secret values. TOML stores only the selected profile and region.
- `config discover` is read-only and reports only source type, availability, profile name, and a redacted fingerprint where appropriate.
- `config import` or `config set-key` requires an explicit user action before a discovered long-lived API key is copied into TranslateKit's Keychain.
- Secret values are accepted from a secure terminal prompt or stdin, never printed, and never required as command-line arguments.

## CLI contract

The executable is named `tkit`. Commands and options are English.

### Translation

```text
tkit translate [TEXT...] [--from CODE] [--to CODE]
               [--provider ID] [--config PATH] [--json]
```

- Positional words are joined with spaces.
- With no positional text, stdin is read to EOF. An interactive terminal with neither source returns a usage error.
- With neither language option, the configured language pair performs the same local direction detection as the app.
- `--to` alone uses provider source auto-detection.
- `--from` alone targets the other configured pair member and fails if the source is outside the pair.
- `--from` plus `--to` uses the explicit direction.
- Plain mode writes only translated text plus one trailing newline to stdout.
- `--json` writes a stable object with source text, translation, detected source language, target language, provider ID, and character count.
- Diagnostics and errors go to stderr.

### Configuration

```text
tkit config init
tkit config path
tkit config show [--json]
tkit config get KEY
tkit config set KEY VALUE
tkit config unset KEY
tkit config discover [PROVIDER] [--json]
tkit config import PROVIDER
tkit config set-key PROVIDER
tkit config delete-key PROVIDER
```

`set-key` reads from a secure prompt when attached to a terminal and from stdin otherwise. `show` and JSON output never include secrets, only whether a usable credential source exists.

### Provider inspection

```text
tkit providers list [--json]
```

The command reports stable ID, name, privacy classification, configuration state, credential source type, and availability without making a paid translation request.

## App integration

- Settings uses the shared configuration store for language pair, active provider, endpoints, plan, AWS profile, and region.
- The API-key section follows the already approved aligned native layout and extends it to Azure and LibreTranslate.
- AWS shows discovered profile names and a manual static-credential fallback behind an explicit advanced action.
- A credential save is reported as successful only after the Keychain operation succeeds.
- The backend picker lists all providers. Unconfigured providers remain visible and explain what is missing instead of disappearing.
- Privacy copy identifies which providers send text to external servers.
- The GUI reloads provider availability after configuration or Keychain changes.

## Translation flow

1. App or CLI loads and validates configuration.
2. Language direction is derived from explicit arguments or the configured pair.
3. The provider registry builds the selected backend with its non-secret options.
4. The credential resolver selects a permitted source without logging a secret.
5. The backend performs exactly one translation request.
6. The result is normalized into `TranslationResult` and rendered by the caller.

## Error handling

Errors distinguish:

- invalid CLI usage;
- missing or invalid configuration;
- missing credentials;
- unsupported language or pair;
- Apple model not installed;
- network failure;
- authentication failure;
- rate or quota exhaustion;
- malformed provider response.

The CLI uses exit code `2` for usage errors, `3` for configuration or credential errors, and `1` for translation/provider failures. JSON mode emits a structured error object to stderr. HTTP errors are sanitized and never include request headers, tokens, or full provider response bodies.

## Security

- No secret appears in TOML, stdout, logs, process arguments, or error descriptions.
- Endpoint overrides are validated before attaching credentials.
- Provider credentials are sent only to the provider's fixed official host, except for the explicitly configured LibreTranslate endpoint.
- LibreTranslate redirects to a different host are rejected when an API key is present.
- Keychain and process access are abstracted behind small protocols so tests never touch the real login Keychain.
- AWS static credentials are a manual fallback. Native profiles and short-lived credentials are preferred.

## Packaging

- SwiftPM produces both `TranslateKit` and `tkit` products.
- The app bundle contains `tkit` as a signed auxiliary executable in `Contents/MacOS`.
- Source builds can run `swift run tkit`.
- Make targets build and test both products without removing the existing stable code-signing workflow.
- Distribution metadata can expose the bundled auxiliary executable on `PATH`; publishing the external Homebrew change remains a separate release action.

## Dependencies

- `swift-argument-parser` 1.8.2 for the async CLI command tree.
- `swift-toml` 2.0.0 for spec-compliant Codable TOML parsing and encoding.
- AWS SDK for Swift 1.7.4, using only the Amazon Translate product and standard credential providers.
- Existing `KeyboardShortcuts` dependency remains app-only.

## Verification

- Unit tests cover BCP-47 validation, language-pair detection, TOML defaults/round trips/migration, atomic writes, endpoint validation, credential precedence, and redaction.
- REST provider tests use an injected HTTP client and deterministic fixtures for success, detection, auth failures, quota failures, unsupported languages, and malformed responses.
- AWS uses an injected client protocol; tests never call AWS.
- CLI tests cover positional input, stdin, plain output, JSON output, config commands, secret redaction, and exit-code mapping.
- Existing Accessibility, Services, hotkey, and signing tests remain green after target separation.
- `swift test` and debug/release builds succeed.
- Smoke tests run `tkit --help`, `tkit providers list`, a temporary-config workflow, and Apple CLI translation when the required local model is installed.
- The installed app still launches, exposes Settings, and uses the same configured provider and language pair as `tkit`.
