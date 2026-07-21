# Settings sidebar and provider management: design

## Status

Visual design approved on 2026-07-21. This specification supersedes the narrow API-key layout from `2026-07-18-api-keys-settings-design.md` and complements the implemented provider and CLI design in `2026-07-18-providers-cli-config-design.md`.

## Goal

Turn the growing single-page Settings form into a native macOS settings surface that remains understandable as TranslateKit adds provider-specific configuration. Keep provider setup separate from choosing the active translation engine.

## Scope

- Replace the single scrolling form with persistent category navigation.
- Add a dedicated provider catalog with provider-specific details.
- Reuse `ProviderRegistry`, `ProviderState`, `PreferencesManager`, `BackendManager`, `CredentialResolver`, and the shared TOML configuration.
- Preserve all current General, language, hotkey, Accessibility, Apple language-pack, provider, credential, privacy, and configuration-error behavior.
- Remove the bottom `Done` action. The title-bar close control closes the window; ordinary preferences apply immediately, while credential changes keep explicit actions.
- Use native SwiftUI and AppKit controls, system typography, SF Symbols, current accent color, keyboard navigation, and VoiceOver labels.

## Non-goals

- No new provider, backend, credential source, login flow, or paid validation request.
- No automatic provider fallback.
- No credential import without an explicit user action.
- No search field while the settings surface contains only four categories and six providers.
- No `Appearance` category until TranslateKit has at least one real appearance preference.
- No reusable schema that tries to render every provider form from generic field metadata. Provider details remain type-specific.

## Information architecture

The root sidebar contains four peer categories in this order:

1. `General`
2. `Translation`
3. `Shortcuts`
4. `Providers`

The most recently selected category is restored when Settings reopens. New categories are added only when they contain real settings.

### General

- Launch at login.
- Show menu bar icon.
- Global configuration errors remain visible above the current category content because invalid TOML affects the entire app.

### Translation

- First language.
- Second language.
- Apple language-pack availability and download action.
- Active engine.
- Privacy explanation for the active engine.
- An unconfigured provider remains visible in the engine picker. Selecting it shows what is missing and provides `Configure Provider...`, which opens the matching provider detail without silently changing credentials or falling back to another service.

### Shortcuts

- Translate selection shortcut.
- Translate and replace shortcut.
- Accessibility permission status and recovery action.

### Providers

The Providers category has two internal columns:

- a provider list in stable `ProviderRegistry.descriptors` order;
- the configuration detail for the selected provider.

The category sidebar remains visible while browsing providers. The provider list and its detail are peers inside the Providers page, not modal sheets or expanding cards. The last provider selected during the current Settings session remains selected.

## Window and navigation

- Use a native split-view layout with a category sidebar and a detail area.
- The Providers detail area adds a provider list and provider-specific content, matching the approved three-column preview at wide sizes.
- The category sidebar uses concise labels and system symbols. Selection never depends on color alone.
- Allow the category sidebar to collapse through the standard split-view control.
- Give the provider detail enough width for Azure, AWS, and LibreTranslate forms without fixed field widths that truncate localized content.
- Establish a practical minimum size and allow resizing instead of hardcoding the current 520 by 640 point window.
- Keep one canonical Settings surface. The SwiftUI `Settings` scene and the AppDelegate entry point must open or focus the same settings experience, not create independent windows with divergent state or sizing.
- Persist the selected category, but not partially entered secrets.

## Provider list

Rows are generated from `BackendManager.providers`; provider names and ordering are not duplicated in the view.

Each row shows:

- provider name;
- a text status paired with a system symbol;
- relevant non-secret context, such as an AWS profile count or credential source.

Presentation is derived from current provider data:

- Apple: `Built in`.
- Key-based cloud provider with a usable discovered credential: `Configured`.
- Key-based cloud provider without a usable credential: `Needs setup`.
- AWS with discovered profiles: profile count plus its configured or setup status.
- LibreTranslate: configured endpoint state, without claiming that the remote server is reachable.
- Refresh in progress: `Checking...`.

`Configured` means configuration or credentials were discovered. It does not claim that authentication, quota, billing, network access, or the selected language pair was verified.

A `Refresh` action reruns `BackendManager.reload()` and keeps the current selection and keyboard focus when the provider still exists.

## Provider details

All provider details share a header with name, privacy boundary, current non-secret status, and credential source. They do not contain an action that silently makes the provider active. Engine selection remains in Translation.

### Apple Translation

- State that translation is on-device and needs no credential.
- Show current language-pack status.
- Link to the Translation category for language and model management.

### DeepL

- Free or Pro account selection.
- API-key presence and source.
- Explicit `Add Key`, `Replace Key`, and `Remove Key` actions.
- Link to create a DeepL API key.

### Google Cloud Translation

- Authentication mode: Automatic, API key, or gcloud.
- Discovered credential source.
- API-key add, replace, and remove actions when API-key mode applies.
- Link to Google Cloud credentials.

### Azure Translator

- Authentication mode: Automatic, API key, or Entra CLI.
- Endpoint and region.
- Discovered credential source.
- API-key add, replace, and remove actions when API-key mode applies.

### Amazon Translate

- Authentication mode: profile or native chain, or static credentials.
- Discovered profile picker and default-chain option.
- Region.
- Static access key ID, secret access key, and optional session token behind an explicit advanced action.
- Static-credential add, replace, and remove actions.

### LibreTranslate-compatible

- Endpoint.
- Optional API-key presence and source.
- API-key add, replace, and remove actions.
- State clearly that text goes only to the configured endpoint.

## Secrets and save behavior

- Never prefill a field with a stored or discovered secret.
- Represent an existing TranslateKit Keychain item as `Saved in Keychain`.
- Discovered external credentials show only the allowlisted source type and non-secret metadata already exposed by `ProviderState`.
- `Add Key` or `Replace Key` reveals an empty `SecureField` for the selected provider only.
- Credential save is successful only when Keychain or `CredentialResolver` returns success. Then refresh provider state.
- `Remove Key` is explicit. If the credential belongs to the active provider, warn that future translations will fail until another usable source is selected or a new credential is saved.
- Failed persistence keeps the editor open, preserves the entered value for retry, and shows a local actionable error.
- Secret values never enter TOML, UserDefaults, logs, status copy, accessibility values, or provider-list rows.

Non-secret TOML settings continue to use `PreferencesManager`. Values that already require explicit validation and save, such as custom endpoints, retain an explicit save action and local validation feedback.

## Components and ownership

`SettingsView` becomes a navigation shell instead of owning every control and secret field.

```text
SettingsView
  SettingsSidebar
  GeneralSettingsView
  TranslationSettingsView
  ShortcutsSettingsView
  ProvidersSettingsView
    ProviderList
    ProviderDetailView
      AppleProviderSettingsView
      DeepLProviderSettingsView
      GoogleCloudProviderSettingsView
      AzureProviderSettingsView
      AWSProviderSettingsView
      LibreTranslateProviderSettingsView
```

Shared UI state is limited to:

- selected settings category;
- selected provider;
- refresh state;
- the draft and persistence state for the currently edited credential.

The existing domain types remain authoritative:

- `ProviderRegistry` owns provider identity, order, privacy, and credential requirements.
- `BackendManager` owns provider discovery state and the active provider.
- `PreferencesManager` owns GUI state plus validated shared configuration updates.
- `CredentialResolver` and Keychain abstractions own secret persistence and discovery.

Provider-specific views may share small credential controls, but there is no large switch-filled generic form or second provider registry in the UI.

## Error handling

- Invalid TOML remains untouched and produces a global configuration warning with its path.
- Local field validation appears next to the affected field.
- Credential persistence errors appear in the selected provider detail.
- Discovery failures keep the provider visible and show `Could not check configuration`; they do not remove the row.
- Removing or invalidating the active provider never triggers automatic fallback.
- Refresh and async discovery can be cancelled when Settings closes without losing persisted data.

## Accessibility and keyboard behavior

- Category and provider lists expose a selected row, label, symbol, and textual status.
- Changing provider moves VoiceOver context to the detail heading without forcing keyboard focus into a field.
- Every `SecureField`, picker, button, and status has a provider-specific accessible label.
- Status is communicated through text and symbol, never color alone.
- Native tab order runs category sidebar, provider list when present, then provider detail.
- All external links describe their destination rather than using generic copy.

## Verification

- Unit-test the pure mapping from `ProviderState` plus configuration to provider-list presentation.
- Unit-test category routing and the navigation action from an unconfigured engine to its provider detail.
- Unit-test credential editor states: absent, saved, dirty, saving, saved, failed, and removal warning for the active provider.
- Keep provider, configuration, credential, CLI, Accessibility, signing, and packaging tests green.
- Run `swift test` and debug plus release builds.
- Render Settings at minimum and expanded sizes. Verify all categories and all six provider details without clipping.
- Verify keyboard-only navigation through categories, provider list, credential editing, save, remove, refresh, links, and sidebar collapse.
- Verify VoiceOver labels and status announcements.
- Verify both Settings entry points focus the same window and preserve category selection.
- Verify no secret appears in TOML, UserDefaults, logs, screenshots, provider rows, or accessibility output.
