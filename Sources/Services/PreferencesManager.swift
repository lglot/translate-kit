import Foundation
import TranslateKitCore

@MainActor
final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private let defaults: UserDefaults
    private let configurationStore: ConfigurationStore
    private var canPersistConfiguration: Bool
    private var isRollingBack = false

    @Published var firstLanguage: Language {
        didSet { persistOrRollback(oldValue) { firstLanguage = $0 } }
    }

    @Published var secondLanguage: Language {
        didSet { persistOrRollback(oldValue) { secondLanguage = $0 } }
    }

    @Published var activeBackendID: String {
        didSet { persistOrRollback(oldValue) { activeBackendID = $0 } }
    }

    @Published var deeplIsPro: Bool {
        didSet { persistOrRollback(oldValue) { deeplIsPro = $0 } }
    }

    @Published var googleCloudAuth: String {
        didSet { persistOrRollback(oldValue) { googleCloudAuth = $0 } }
    }

    @Published var azureAuth: String {
        didSet { persistOrRollback(oldValue) { azureAuth = $0 } }
    }

    @Published var azureEndpoint: String {
        didSet { persistOrRollback(oldValue) { azureEndpoint = $0 } }
    }

    @Published var azureRegion: String {
        didSet { persistOrRollback(oldValue) { azureRegion = $0 } }
    }

    @Published var awsAuth: String {
        didSet { persistOrRollback(oldValue) { awsAuth = $0 } }
    }

    @Published var awsProfile: String {
        didSet { persistOrRollback(oldValue) { awsProfile = $0 } }
    }

    @Published var awsRegion: String {
        didSet { persistOrRollback(oldValue) { awsRegion = $0 } }
    }

    @Published var libreTranslateEndpoint: String {
        didSet { persistOrRollback(oldValue) { libreTranslateEndpoint = $0 } }
    }

    @Published private(set) var configurationError: String?

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var languagePair: LanguagePair {
        LanguagePair(first: firstLanguage, second: secondLanguage)
    }

    var configuration: TranslateKitConfiguration {
        TranslateKitConfiguration(
            translation: TranslationConfiguration(
                provider: activeBackendID,
                firstLanguage: firstLanguage.rawValue,
                secondLanguage: secondLanguage.rawValue
            ),
            providers: ProviderConfigurations(
                deepl: DeepLConfiguration(plan: deeplIsPro ? "pro" : "free"),
                googleCloud: GoogleCloudConfiguration(auth: googleCloudAuth),
                azure: AzureConfiguration(
                    auth: azureAuth,
                    endpoint: azureEndpoint,
                    region: azureRegion
                ),
                aws: AWSConfiguration(
                    auth: awsAuth,
                    profile: awsProfile,
                    region: awsRegion
                ),
                libretranslate: LibreTranslateConfiguration(endpoint: libreTranslateEndpoint)
            )
        )
    }

    var configurationURL: URL { configurationStore.url }

    func validatedConfiguration() throws -> TranslateKitConfiguration {
        guard canPersistConfiguration else {
            throw ConfigurationError.malformed(
                configurationError ?? "The configuration requires repair"
            )
        }
        let configuration = configuration
        try configuration.validate()
        return configuration
    }

    func setAzureEndpoint(_ endpoint: String) throws {
        try updateConfiguration { configuration in
            configuration.providers.azure.endpoint = endpoint
        }
    }

    func setLibreTranslateEndpoint(_ endpoint: String) throws {
        try updateConfiguration { configuration in
            configuration.providers.libretranslate.endpoint = endpoint
        }
    }

    init(
        defaults: UserDefaults = .standard,
        configurationStore: ConfigurationStore = ConfigurationStore()
    ) {
        self.defaults = defaults
        self.configurationStore = configurationStore

        let legacy = LegacyTranslationPreferences(
            provider: defaults.string(forKey: Keys.activeBackend) ?? "apple",
            firstLanguage: defaults.string(forKey: Keys.firstLanguage) ?? "it",
            secondLanguage: defaults.string(forKey: Keys.secondLanguage) ?? "en",
            deeplPlan: defaults.bool(forKey: Keys.deeplIsPro) ? "pro" : "free"
        )

        let loaded: TranslateKitConfiguration
        do {
            loaded = try configurationStore.loadOrCreate(legacy: legacy)
            canPersistConfiguration = true
            configurationError = nil
            defaults.set(true, forKey: Keys.configurationMigrationCompleted)
        } catch {
            loaded = .default
            canPersistConfiguration = false
            configurationError = error.localizedDescription
        }

        firstLanguage = Language(rawValue: loaded.translation.firstLanguage) ?? .italian
        secondLanguage = Language(rawValue: loaded.translation.secondLanguage) ?? .english
        activeBackendID = loaded.translation.provider
        deeplIsPro = loaded.providers.deepl.plan == "pro"
        googleCloudAuth = loaded.providers.googleCloud.auth
        azureAuth = loaded.providers.azure.auth
        azureEndpoint = loaded.providers.azure.endpoint
        azureRegion = loaded.providers.azure.region
        awsAuth = loaded.providers.aws.auth
        awsProfile = loaded.providers.aws.profile
        awsRegion = loaded.providers.aws.region
        libreTranslateEndpoint = loaded.providers.libretranslate.endpoint

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    func reloadConfiguration() {
        do {
            let loaded = try configurationStore.load()
            apply(loaded)
            canPersistConfiguration = true
            configurationError = nil
        } catch {
            canPersistConfiguration = false
            configurationError = error.localizedDescription
        }
    }

    private func apply(_ configuration: TranslateKitConfiguration) {
        isRollingBack = true
        defer { isRollingBack = false }
        firstLanguage = Language(rawValue: configuration.translation.firstLanguage) ?? .italian
        secondLanguage = Language(rawValue: configuration.translation.secondLanguage) ?? .english
        activeBackendID = configuration.translation.provider
        deeplIsPro = configuration.providers.deepl.plan == "pro"
        googleCloudAuth = configuration.providers.googleCloud.auth
        azureAuth = configuration.providers.azure.auth
        azureEndpoint = configuration.providers.azure.endpoint
        azureRegion = configuration.providers.azure.region
        awsAuth = configuration.providers.aws.auth
        awsProfile = configuration.providers.aws.profile
        awsRegion = configuration.providers.aws.region
        libreTranslateEndpoint = configuration.providers.libretranslate.endpoint
    }

    private func persistOrRollback<T>(_ oldValue: T, rollback: (T) -> Void) {
        guard !isRollingBack else { return }
        do {
            guard canPersistConfiguration else {
                throw PreferencesConfigurationError.configurationRequiresRepair
            }
            try configurationStore.save(configuration)
            configurationError = nil
        } catch {
            isRollingBack = true
            rollback(oldValue)
            isRollingBack = false
            configurationError = error.localizedDescription
        }
    }

    private func updateConfiguration(
        _ update: (inout TranslateKitConfiguration) -> Void
    ) throws {
        guard canPersistConfiguration else {
            throw PreferencesConfigurationError.configurationRequiresRepair
        }
        var candidate = configuration
        update(&candidate)
        do {
            try configurationStore.save(candidate)
            apply(candidate)
            configurationError = nil
        } catch {
            configurationError = error.localizedDescription
            throw error
        }
    }

    private enum Keys {
        static let firstLanguage = "firstLanguage"
        static let secondLanguage = "secondLanguage"
        static let activeBackend = "activeBackend"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let deeplIsPro = "deeplIsPro"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let configurationMigrationCompleted = "configurationMigrationCompleted"
    }
}

private enum PreferencesConfigurationError: LocalizedError {
    case configurationRequiresRepair

    var errorDescription: String? {
        "Repair the TOML configuration before changing translation settings"
    }
}
