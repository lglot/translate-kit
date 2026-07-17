import Foundation

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    /// Language pair: text detected as `first` is translated to `second` and vice versa.
    @Published var firstLanguage: Language {
        didSet { defaults.set(firstLanguage.rawValue, forKey: Keys.firstLanguage) }
    }

    @Published var secondLanguage: Language {
        didSet { defaults.set(secondLanguage.rawValue, forKey: Keys.secondLanguage) }
    }

    @Published var activeBackendID: String {
        didSet { defaults.set(activeBackendID, forKey: Keys.activeBackend) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published var deeplIsPro: Bool {
        didSet { defaults.set(deeplIsPro, forKey: Keys.deeplIsPro) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var languagePair: LanguagePair {
        LanguagePair(first: firstLanguage, second: secondLanguage)
    }

    private init() {
        let first = defaults.string(forKey: Keys.firstLanguage) ?? "it"
        let second = defaults.string(forKey: Keys.secondLanguage) ?? "en"
        self.firstLanguage = Language(rawValue: first) ?? .italian
        self.secondLanguage = Language(rawValue: second) ?? .english
        self.activeBackendID = defaults.string(forKey: Keys.activeBackend) ?? "apple"
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        self.deeplIsPro = defaults.bool(forKey: Keys.deeplIsPro)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    private enum Keys {
        static let firstLanguage = "firstLanguage"
        static let secondLanguage = "secondLanguage"
        static let activeBackend = "activeBackend"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let deeplIsPro = "deeplIsPro"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
}
