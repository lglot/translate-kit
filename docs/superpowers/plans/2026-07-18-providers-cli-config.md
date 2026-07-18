# Translation Providers, Shared Configuration, and `tkit` CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six translation providers, an open BCP-47 language model, shared TOML and Keychain configuration, and an independent `tkit` CLI without regressing the existing macOS app.

**Architecture:** Split reusable code into `TranslateKitCore`, isolate Apple's hidden SwiftUI translation host in `TranslateKitApple`, and keep the existing app and new CLI as separate executables. App and CLI load the same TOML file, use the same Keychain service, and construct backends through the same registry with no silent provider fallback.

**Tech Stack:** Swift 6 language mode 5, macOS 15+, SwiftPM, Foundation, Security, Translation, AppKit, SwiftUI, swift-argument-parser 1.8.2, swift-toml 2.0.0, AWS SDK for Swift 1.7.4, XCTest.

## Global Constraints

- Executable name is exactly `tkit`; commands and options are English.
- Default configuration path is `~/.config/translate-kit/config.toml`.
- TOML never stores API keys, bearer tokens, AWS secrets, or session tokens.
- Keychain service remains `com.translatekit.app`; existing DeepL and Google accounts remain compatible.
- Provider IDs are `apple`, `deepl`, `google-cloud`, `azure`, `aws`, and `libretranslate`.
- No automatic fallback between providers.
- Plain translation output contains only translated text and one trailing newline.
- Preserve all pre-existing dirty work, especially `Makefile`, `Sources/Services/ReplaceEngine.swift`, and untracked tests and learning material.
- Do not make live paid provider calls in automated tests.

---

## File map

### New shared target

- `Sources/TranslateKitCore/Models/Language.swift`: open BCP-47 value and Foundation language catalog.
- `Sources/TranslateKitCore/Models/LanguagePair.swift`: constrained local pair detection.
- `Sources/TranslateKitCore/Models/TranslationResult.swift`: normalized results and public errors.
- `Sources/TranslateKitCore/Configuration/TranslateKitConfiguration.swift`: Codable TOML schema and validation.
- `Sources/TranslateKitCore/Configuration/ConfigurationStore.swift`: path resolution, atomic persistence, and legacy migration input.
- `Sources/TranslateKitCore/Credentials/SecretStore.swift`: Keychain abstraction and provider secret names.
- `Sources/TranslateKitCore/Credentials/CredentialResolver.swift`: environment, allowlisted Keychain, native CLI, AWS-profile discovery, and redaction.
- `Sources/TranslateKitCore/Credentials/ProcessRunner.swift`: bounded subprocess execution without logging stdout.
- `Sources/TranslateKitCore/HTTP/HTTPClient.swift`: injectable URLSession boundary.
- `Sources/TranslateKitCore/Backends/TranslationBackend.swift`: public backend protocol.
- `Sources/TranslateKitCore/Backends/DeepLBackend.swift`: DeepL REST adapter.
- `Sources/TranslateKitCore/Backends/GoogleCloudBackend.swift`: Google API-key and bearer-token adapter.
- `Sources/TranslateKitCore/Backends/AzureBackend.swift`: Azure API-key and Entra adapter.
- `Sources/TranslateKitCore/Backends/LibreTranslateBackend.swift`: LibreTranslate/LTEngine adapter.
- `Sources/TranslateKitCore/Backends/AWSBackend.swift`: Amazon Translate SDK adapter.
- `Sources/TranslateKitCore/Providers/ProviderRegistry.swift`: descriptors, factories, and configured state.
- `Sources/TranslateKitCore/TranslationService.swift`: explicit backend dispatch and direction resolution.

### Apple adapter

- `Sources/TranslateKitApple/AppleBackend.swift`: public backend wrapper.
- `Sources/TranslateKitApple/AppleTranslationProvider.swift`: hidden TranslationSession host.

### CLI

- `Sources/tkit/TKitCommand.swift`: root command and global configuration-path option.
- `Sources/tkit/TranslateCommand.swift`: text/stdin translation and rendering.
- `Sources/tkit/ConfigCommand.swift`: init/path/show/get/set/unset/discover/import/set-key/delete-key.
- `Sources/tkit/ProvidersCommand.swift`: provider inspection.
- `Sources/tkit/CLIEnvironment.swift`: dependency assembly and exit-safe errors.

### Existing app and support files

- `Package.swift`: four targets and pinned dependencies.
- `Sources/Services/PreferencesManager.swift`: TOML-backed translation preferences, UserDefaults-backed GUI preferences.
- `Sources/Services/BackendManager.swift`: all-provider registry and reload.
- `Sources/Services/TranslationCoordinator.swift`: shared service dispatch.
- `Sources/Utilities/KeychainHelper.swift`: compatibility wrapper around the shared secret store.
- `Sources/Views/SettingsView.swift`: all providers, aligned secure fields, endpoints, AWS profiles, and correct save state.
- `Sources/TranslateKitApp.swift`: configuration error reporting and existing app wiring.
- `Makefile`: build/package `tkit` while retaining the user's stable signing changes.
- `README.md`: providers, CLI, configuration, privacy, and build instructions.

### Tests

- `Tests/LanguageTests.swift`
- `Tests/LanguagePairTests.swift`
- `Tests/ConfigurationStoreTests.swift`
- `Tests/CredentialResolverTests.swift`
- `Tests/RESTBackendTests.swift`
- `Tests/AWSBackendTests.swift`
- `Tests/TranslationServiceTests.swift`
- `Tests/CLIContractTests.swift`

---

### Task 1: Split targets and open the language model

**Files:**
- Modify: `Package.swift`
- Move: `Sources/Models/*.swift` to `Sources/TranslateKitCore/Models/`
- Move: `Sources/Backends/TranslationBackend.swift` to `Sources/TranslateKitCore/Backends/TranslationBackend.swift`
- Move: `Sources/Backends/AppleBackend.swift` to `Sources/TranslateKitApple/AppleBackend.swift`
- Move: `Sources/Services/AppleTranslationProvider.swift` to `Sources/TranslateKitApple/AppleTranslationProvider.swift`
- Modify: `Tests/LanguagePairTests.swift`
- Create: `Tests/LanguageTests.swift`

**Interfaces:**
- Produces: `public struct Language: RawRepresentable, Codable, Hashable, Identifiable, Sendable`.
- Produces: `public struct LanguagePair: Equatable, Sendable`.
- Produces: public `TranslationBackend`, `TranslationResult`, and `TranslationError`.

- [ ] **Step 1: Write failing language tests**

```swift
func testAcceptsRegionalBCP47Code() {
    XCTAssertEqual(Language(rawValue: "pt-BR")?.rawValue, "pt-BR")
}

func testRejectsEmptyAndAutoTarget() {
    XCTAssertNil(Language(rawValue: ""))
    XCTAssertFalse(Language.auto.isValidTarget)
}

func testFoundationCatalogContainsMoreThanLegacySet() {
    XCTAssertGreaterThan(Language.targetLanguages.count, 100)
}
```

- [ ] **Step 2: Run the focused tests and verify the old enum cannot satisfy them**

Run: `swift test --filter LanguageTests` with task-specific module-cache paths.
Expected: FAIL because `pt-BR` is not an enum case and `isValidTarget` does not exist.

- [ ] **Step 3: Define the new value type and public module boundaries**

```swift
public struct Language: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public let rawValue: String
    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == "auto" || Locale.Language(identifier: value).languageCode != nil else { return nil }
        self.rawValue = value
    }
    public static let auto = Language(rawValue: "auto")!
    public static let italian = Language(rawValue: "it")!
    public static let english = Language(rawValue: "en")!
    public var id: String { rawValue }
    public var isValidTarget: Bool { self != .auto }
}
```

Add the remaining existing convenience constants, localized names, common flags, ISO catalog sorting, and public access control required by the app and CLI.

- [ ] **Step 4: Configure the four targets and repair imports**

The app target keeps `path: "Sources"` and excludes `TranslateKitCore`, `TranslateKitApple`, and `tkit`, avoiding any move of the dirty `ReplaceEngine.swift`. The test target depends on `TranslateKit`, `TranslateKitCore`, and `TranslateKitApple`.

- [ ] **Step 5: Run language and existing tests**

Run: `swift test --filter 'LanguageTests|LanguagePairTests'`.
Expected: PASS.

- [ ] **Step 6: Commit the isolated target/language change**

```bash
git add Package.swift Sources/TranslateKitCore Sources/TranslateKitApple Tests/LanguageTests.swift Tests/LanguagePairTests.swift
git commit -m "refactor: split translation targets and open languages"
```

### Task 2: Add typed TOML configuration and migration

**Files:**
- Create: `Sources/TranslateKitCore/Configuration/TranslateKitConfiguration.swift`
- Create: `Sources/TranslateKitCore/Configuration/ConfigurationStore.swift`
- Create: `Tests/ConfigurationStoreTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Produces: `public struct TranslateKitConfiguration: Codable, Equatable, Sendable`.
- Produces: `public struct LegacyTranslationPreferences: Sendable`.
- Produces: `public final class ConfigurationStore: Sendable` with `load()`, `loadOrCreate(legacy:)`, `save(_:)`, and `defaultURL`.

- [ ] **Step 1: Write failing tests for defaults, round-trip, malformed input, unknown keys, and no-rewrite-on-load**

```swift
func testDefaultConfigurationMatchesProductDefaults() {
    let config = TranslateKitConfiguration.default
    XCTAssertEqual(config.translation.provider, "apple")
    XCTAssertEqual(config.translation.firstLanguage, "it")
    XCTAssertEqual(config.translation.secondLanguage, "en")
}

func testLoadDoesNotRewriteExistingFile() throws {
    let before = try Data(contentsOf: url)
    _ = try store.load()
    XCTAssertEqual(try Data(contentsOf: url), before)
}

func testUnknownKeyIsRejected() {
    XCTAssertThrowsError(try store.decode("version = 1\nunknown = true\n"))
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter ConfigurationStoreTests`.
Expected: FAIL because configuration types do not exist.

- [ ] **Step 3: Implement the schema and validation**

Use nested Codable structs for `translation` and each provider section. Validate provider IDs, distinct pair members, source/target rules, DeepL plan, Azure URL, LibreTranslate HTTPS-or-loopback URL, AWS auth mode, and allowed TOML section/key paths.

- [ ] **Step 4: Implement safe persistence**

```swift
public func save(_ configuration: TranslateKitConfiguration) throws {
    try configuration.validate()
    try fileManager.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    let data = try encoder.encode(configuration)
    try data.write(to: url, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
```

- [ ] **Step 5: Implement migration input without coupling Core to UserDefaults**

`loadOrCreate(legacy:)` creates TOML only when missing and uses validated legacy provider, pair, and DeepL plan values. It never rewrites an existing or invalid file.

- [ ] **Step 6: Run focused and complete tests**

Run: `swift test --filter ConfigurationStoreTests` and `swift test`.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/TranslateKitCore/Configuration Tests/ConfigurationStoreTests.swift
git commit -m "feat: add shared TOML configuration"
```

### Task 3: Add secret storage and credential discovery

**Files:**
- Create: `Sources/TranslateKitCore/Credentials/SecretStore.swift`
- Create: `Sources/TranslateKitCore/Credentials/ProcessRunner.swift`
- Create: `Sources/TranslateKitCore/Credentials/CredentialResolver.swift`
- Create: `Tests/CredentialResolverTests.swift`
- Modify: `Sources/Utilities/KeychainHelper.swift`

**Interfaces:**
- Produces: `public protocol SecretStore: Sendable`.
- Produces: `public enum ProviderCredential: Sendable { case apiKey(String), bearerToken(String), awsProfile(String?), awsStatic(...), none }`.
- Produces: `public struct CredentialDiscovery: Codable, Sendable` with no secret-bearing fields.
- Produces: `public actor ProcessRunner` with bounded output and timeout.

- [ ] **Step 1: Write failing precedence and redaction tests**

```swift
func testTranslateKitKeychainWinsOverEnvironment() async throws {
    let resolver = CredentialResolver(secretStore: storeWithKey("saved"), environment: ["DEEPL_AUTH_KEY": "env"])
    XCTAssertEqual(try await resolver.resolve(for: .deepl), .apiKey("saved"))
}

func testDiscoveryNeverContainsSecretValue() async throws {
    let result = try await resolver.discover(provider: .deepl)
    XCTAssertFalse(String(describing: result).contains("saved"))
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter CredentialResolverTests`.
Expected: FAIL because resolver types do not exist.

- [ ] **Step 3: Implement Keychain and environment resolution**

Keep service `com.translatekit.app`, preserve `deepl_api_key` and `google_cloud_api_key`, and add Azure, LibreTranslate, and optional AWS static accounts. Query only the allowlisted external DeepL service/account pair.

- [ ] **Step 4: Implement native discovery**

- Google: locate `gcloud`, detect ADC, and obtain a bearer token only during a translation attempt.
- Azure: locate `az`, check account state, and obtain a Cognitives Services bearer token only during a translation attempt.
- AWS: parse profile section names from the standard shared files without returning credential values; the SDK performs actual resolution and refresh.

- [ ] **Step 5: Wrap the legacy app helper**

`KeychainHelper` delegates to `KeychainSecretStore` so current GUI call sites retain behavior while moving ownership into Core.

- [ ] **Step 6: Run tests and commit**

Run: `swift test --filter CredentialResolverTests` and `swift test`.
Expected: PASS.

```bash
git add Sources/TranslateKitCore/Credentials Sources/Utilities/KeychainHelper.swift Tests/CredentialResolverTests.swift
git commit -m "feat: discover and store provider credentials safely"
```

### Task 4: Implement REST translation providers

**Files:**
- Create: `Sources/TranslateKitCore/HTTP/HTTPClient.swift`
- Move and rewrite: `Sources/Backends/DeepLBackend.swift`
- Move and rewrite: `Sources/Backends/GoogleCloudBackend.swift`
- Create: `Sources/TranslateKitCore/Backends/AzureBackend.swift`
- Create: `Sources/TranslateKitCore/Backends/LibreTranslateBackend.swift`
- Create: `Tests/RESTBackendTests.swift`

**Interfaces:**
- Produces: `public protocol HTTPClient: Sendable { func data(for: URLRequest) async throws -> (Data, HTTPURLResponse) }`.
- Produces: four `TranslationBackend` implementations initialized with configuration, credential resolver, and HTTP client.

- [ ] **Step 1: Write fixture-driven failing tests**

```swift
func testAzureTranslatesAndReportsDetectedLanguage() async throws {
    let backend = AzureBackend(configuration: azureConfig, credentials: apiKeyResolver, http: fixtureHTTP(azureSuccess))
    let result = try await backend.translate("ciao", from: .auto, to: .english)
    XCTAssertEqual(result.translatedText, "hello")
    XCTAssertEqual(result.sourceLanguage, .italian)
}

func testLibreRejectsCredentialRedirectToDifferentHost() async {
    await XCTAssertThrowsErrorAsync(try await backend.translate("ciao", from: .italian, to: .english))
}
```

Cover success, source detection, missing key, 401/403, 429/quota, unsupported language, malformed JSON, HTML entity behavior, endpoint validation, and credential-bearing redirect rejection.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter RESTBackendTests`.
Expected: FAIL because new adapters and HTTP boundary do not exist.

- [ ] **Step 3: Implement the HTTP boundary and sanitized response mapping**

`URLSessionHTTPClient` disables automatic cross-host credential redirects and maps transport errors to `TranslationError.noInternet` or provider failures without including headers or response bodies.

- [ ] **Step 4: Implement DeepL and Google**

DeepL sends `Authorization: DeepL-Auth-Key`, chooses Free/Pro host from TOML, and maps `detected_source_language`. Google uses API-key query authentication or `Authorization: Bearer`, sends UTF-8 JSON/form data, and maps `detectedSourceLanguage`.

- [ ] **Step 5: Implement Azure and LibreTranslate**

Azure uses `Ocp-Apim-Subscription-Key` plus optional region or bearer auth. LibreTranslate sends JSON `{q, source, target, format, api_key?}` to the validated configured endpoint and accepts the compatible LTEngine response shape.

- [ ] **Step 6: Run tests and commit**

Run: `swift test --filter RESTBackendTests` and `swift test`.
Expected: PASS.

```bash
git add Sources/TranslateKitCore/HTTP Sources/TranslateKitCore/Backends Tests/RESTBackendTests.swift
git commit -m "feat: add cloud REST translation providers"
```

### Task 5: Implement Amazon Translate through the AWS SDK

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TranslateKitCore/Backends/AWSBackend.swift`
- Create: `Tests/AWSBackendTests.swift`

**Interfaces:**
- Produces: `public protocol AWSTranslating: Sendable` to isolate generated SDK types from business tests.
- Produces: `public struct AWSBackend: TranslationBackend`.

- [ ] **Step 1: Write failing adapter tests**

```swift
func testAWSMapsAutoToAmazonAutoCode() async throws {
    let client = RecordingAWSTranslator(output: .init(text: "hello", source: "it"))
    let backend = AWSBackend(client: client)
    _ = try await backend.translate("ciao", from: .auto, to: .english)
    XCTAssertEqual(client.lastInput?.sourceLanguageCode, "auto")
}
```

Also test missing region/profile configuration, translated text normalization, unsupported-language mapping, throttling, and auth failures.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter AWSBackendTests`.
Expected: FAIL because the AWS adapter does not exist.

- [ ] **Step 3: Add only the required AWS products**

Add `AWSTranslate` and `AWSSDKIdentity` from AWS SDK for Swift 1.7.4. Use `ProfileAWSCredentialIdentityResolver` for an explicit profile and the default chain when profile is empty. Use static Keychain credentials only when TOML selects `auth = "static"`.

- [ ] **Step 4: Implement the generated-client wrapper and error mapping**

Construct `TranslateClient.TranslateClientConfiguration` with resolved region and credential identity resolver, call `translateText`, and translate generated service errors into sanitized `TranslationError` cases.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter AWSBackendTests` and `swift test`.
Expected: PASS without contacting AWS.

```bash
git add Package.swift Package.resolved Sources/TranslateKitCore/Backends/AWSBackend.swift Tests/AWSBackendTests.swift
git commit -m "feat: add Amazon Translate provider"
```

### Task 6: Complete Apple adapter, provider registry, and translation service

**Files:**
- Modify: `Sources/TranslateKitApple/AppleBackend.swift`
- Modify: `Sources/TranslateKitApple/AppleTranslationProvider.swift`
- Create: `Sources/TranslateKitCore/Providers/ProviderRegistry.swift`
- Create: `Sources/TranslateKitCore/TranslationService.swift`
- Create: `Tests/TranslationServiceTests.swift`

**Interfaces:**
- Produces: `public enum ProviderID: String, CaseIterable, Codable, Sendable`.
- Produces: `public struct ProviderDescriptor: Codable, Sendable`.
- Produces: `public struct TranslationRequest: Sendable`.
- Produces: `public struct TranslationService: Sendable` with exactly one selected backend per request.

- [ ] **Step 1: Write failing registry and no-fallback tests**

```swift
func testRegistryContainsAllStableProviderIDs() {
    XCTAssertEqual(Set(ProviderID.allCases.map(\.rawValue)), ["apple", "deepl", "google-cloud", "azure", "aws", "libretranslate"])
}

func testTranslationFailureDoesNotCallAnotherProvider() async {
    await XCTAssertThrowsErrorAsync(try await service.translate(request))
    XCTAssertEqual(fallback.calls, 0)
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter TranslationServiceTests`.
Expected: FAIL because registry and service do not exist.

- [ ] **Step 3: Export and harden the Apple adapter**

Make the existing provider public inside `TranslateKitApple`, initialize the minimal AppKit runtime only on Apple requests, retain the invisible host window, and preserve model-availability and timeout behavior.

- [ ] **Step 4: Implement registry, backend assembly, and direction resolution**

The service resolves explicit `from/to` or configured-pair behavior, selects one backend by `ProviderID`, and never retries another provider.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter TranslationServiceTests` and `swift test`.
Expected: PASS.

```bash
git add Sources/TranslateKitApple Sources/TranslateKitCore/Providers Sources/TranslateKitCore/TranslationService.swift Tests/TranslationServiceTests.swift
git commit -m "feat: unify provider dispatch"
```

### Task 7: Implement the `tkit` command tree

**Files:**
- Create: `Sources/tkit/TKitCommand.swift`
- Create: `Sources/tkit/CLIEnvironment.swift`
- Create: `Sources/tkit/TranslateCommand.swift`
- Create: `Sources/tkit/ConfigCommand.swift`
- Create: `Sources/tkit/ProvidersCommand.swift`
- Create: `Tests/CLIContractTests.swift`

**Interfaces:**
- Produces: async `tkit translate`, `tkit config`, and `tkit providers` commands.
- Consumes: `ConfigurationStore`, `CredentialResolver`, `ProviderRegistry`, `TranslationService`, and `AppleBackend`.

- [ ] **Step 1: Write failing CLI contract tests**

```swift
func testPlainRendererOutputsOnlyTranslation() throws {
    XCTAssertEqual(try TranslationRenderer.plain(result), "hello\n")
}

func testJSONRendererUsesStableProviderID() throws {
    let output = try TranslationRenderer.json(result)
    XCTAssertTrue(output.contains(#"\"provider\":\"deepl\""#))
}
```

Add tests for positional joining, stdin, no-input error, pair direction, `--to`, config path/show/set/unset, redaction, discovery, and exit-code categories.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter CLIContractTests`.
Expected: FAIL because CLI helpers do not exist.

- [ ] **Step 3: Implement root and translation commands**

Use `AsyncParsableCommand`. Root exposes global `--config`. Translation reads positional text or stdin, builds one request, writes plain or JSON output to stdout, and sends diagnostics only to stderr.

- [ ] **Step 4: Implement configuration commands**

Use a fixed dotted-key allowlist. `set-key` reads with `readpassphrase` on a TTY or stdin otherwise. `show`, `get`, `discover`, and JSON output contain no secret value. `import` copies only a discovered long-lived key after an explicit command.

- [ ] **Step 5: Implement provider inspection**

List all providers and merge descriptor data with credential discovery. Do not make a translation request.

- [ ] **Step 6: Run CLI tests and smoke help**

Run: `swift test --filter CLIContractTests`, `swift run tkit --help`, and `swift run tkit providers list --json`.
Expected: tests PASS; help includes `translate`, `config`, `providers`; provider JSON contains six entries and no secret fields.

- [ ] **Step 7: Commit**

```bash
git add Sources/tkit Tests/CLIContractTests.swift
git commit -m "feat: add tkit command line interface"
```

### Task 8: Migrate the app to shared state and expose every provider

**Files:**
- Modify: `Sources/Services/PreferencesManager.swift`
- Modify: `Sources/Services/BackendManager.swift`
- Modify: `Sources/Services/TranslationCoordinator.swift`
- Modify: `Sources/Views/SettingsView.swift`
- Modify: `Sources/TranslateKitApp.swift`
- Test: existing app tests plus focused configuration tests

**Interfaces:**
- `PreferencesManager` publishes TOML-backed provider/pair/options and UserDefaults-backed GUI state.
- `BackendManager` lists all providers and builds them from shared dependencies.

- [ ] **Step 1: Add failing migration and visibility assertions**

Test that legacy pair/provider values initialize a missing TOML file and that all six provider descriptors remain visible even without credentials.

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter 'ConfigurationStoreTests|TranslationServiceTests'`.
Expected: FAIL on app migration/visibility cases.

- [ ] **Step 3: Move translation preferences to TOML**

Initialize the store with legacy values only when the file is absent. Persist pair, provider, and DeepL plan atomically on changes. Keep onboarding, launch-at-login, menu-bar visibility, and hotkeys in their current stores.

- [ ] **Step 4: Replace disappearing backends with configured-state rows**

`BackendManager.reload()` keeps Apple, DeepL, Google, Azure, AWS, and LibreTranslate in stable order. Selecting an unconfigured provider is allowed; translation returns an actionable missing-credential/config error.

- [ ] **Step 5: Implement the approved native settings layout**

Use equal-width secure fields and per-provider Save/Saved/Error state. Add Azure region/endpoint, LibreTranslate endpoint, AWS profile/region, discovery status, and privacy text. Save success depends on the Keychain return value.

- [ ] **Step 6: Run tests and build**

Run: `swift test` and `swift build`.
Expected: PASS with both executable products built.

- [ ] **Step 7: Commit only project-owned changes**

Do not stage the pre-existing dirty `ReplaceEngine.swift` or its untracked test.

```bash
git add Sources/Services/PreferencesManager.swift Sources/Services/BackendManager.swift Sources/Services/TranslationCoordinator.swift Sources/Views/SettingsView.swift Sources/TranslateKitApp.swift
git commit -m "feat: share provider settings with the app"
```

### Task 9: Package and document the CLI

**Files:**
- Modify: `Makefile`
- Modify: `README.md`
- Modify: `Resources/Info.plist` only if bundle metadata requires the auxiliary executable declaration
- Add tests to existing `Tests/MakefileSigningTests.swift` only if doing so does not overwrite user work; otherwise create `Tests/CLIPackagingTests.swift`

**Interfaces:**
- Produces both executable products in debug and universal release builds.
- Places signed `tkit` in `TranslateKit.app/Contents/MacOS/tkit`.

- [ ] **Step 1: Write a packaging assertion without replacing the user's untracked test**

```swift
func testMakefilePackagesTKitAuxiliaryExecutable() throws {
    XCTAssertTrue(makefile.contains("Contents/MacOS/tkit"))
    XCTAssertTrue(makefile.contains("swift build --product tkit"))
}
```

- [ ] **Step 2: Run the packaging test and verify failure**

Run: `swift test --filter CLIPackagingTests`.
Expected: FAIL because Makefile does not package `tkit`.

- [ ] **Step 3: Merge CLI packaging into the dirty Makefile surgically**

Retain `CODE_SIGN_IDENTITY_NAME`, fingerprint resolution, and stable signing edits. Add explicit app/CLI product paths, copy `tkit` into the bundle before signing, and add `run-cli` without deleting existing targets.

- [ ] **Step 4: Update README**

Document six providers, free/local privacy boundaries, CLI examples, TOML schema/path, Keychain behavior, AWS profile discovery, source builds, and the lack of automatic provider fallback.

- [ ] **Step 5: Run tests and release build**

Run: `swift test`, `swift build -c release`, and the existing universal `make release` if the current signing identity is available.
Expected: all tests PASS; both `TranslateKit` and `tkit` exist; bundle contains both signed executables.

- [ ] **Step 6: Commit without absorbing unrelated user edits**

Because Makefile already contains user changes needed by its untracked signing test, stage the combined intended Makefile only after reviewing the exact diff and explicitly report that it includes preserved pre-existing signing work.

```bash
git add Makefile README.md Tests/CLIPackagingTests.swift
git commit -m "docs: package and document tkit"
```

### Task 10: Complete verification, review, and completion audit

**Files:**
- Modify only files required by defects found during verification.

**Interfaces:**
- Produces evidence for every design-spec requirement.

- [ ] **Step 1: Run formatting and static checks available in the repository**

Run: `git diff --check` and `swift package describe`.
Expected: no whitespace errors; four intended targets and two executable products are present.

- [ ] **Step 2: Run full automated verification**

Run with task-specific cache paths: `swift test`, `swift build`, and `swift build -c release`.
Expected: PASS.

- [ ] **Step 3: Run CLI smoke tests with an isolated temporary configuration**

```bash
swift run tkit --help
swift run tkit providers list --json
swift run tkit --config /tmp/translatekit-smoke/config.toml config init
swift run tkit --config /tmp/translatekit-smoke/config.toml config set translation.provider apple
printf 'ciao' | swift run tkit --config /tmp/translatekit-smoke/config.toml translate --to en
```

Expected: help and config operations succeed; provider list has six IDs; Apple translation succeeds if the local model is installed, otherwise returns the precise model-not-downloaded error without hanging.

- [ ] **Step 4: Verify secret safety**

Search generated TOML, CLI stdout/stderr fixtures, README examples, and tracked files for test secret values. Confirm `config show`, `discover`, and provider JSON expose only redacted metadata.

- [ ] **Step 5: Verify app and package behavior**

Inspect the bundle, executable names, signatures, and Info.plist together. Launch the app when permitted, open Settings, verify all providers remain visible, and confirm the language picker is no longer restricted to the legacy 27 entries.

- [ ] **Step 6: Request mandatory Swift and general code review**

Run the required Swift reviewer and code reviewer on the final diff. Apply only evidence-backed fixes, then rerun affected tests.

- [ ] **Step 7: Audit the design spec requirement by requirement**

Record each requirement as proven, contradicted, or missing using current files and command output. Continue implementation for any item not proven.

- [ ] **Step 8: Commit final fixes and report without pushing**

Run `git diff --name-only`, review every listed path, and stage each implementation-owned fix by its exact path. If verification produced fixes, commit them with `git commit -m "fix: complete provider and CLI verification"`. If it produced no fixes, skip this commit. Do not push. Report remaining pre-existing dirty files separately from implementation changes.
