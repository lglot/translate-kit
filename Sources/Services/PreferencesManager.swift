import Foundation

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    @Published var targetLanguage: Language {
        didSet { defaults.set(targetLanguage.rawValue, forKey: Keys.targetLanguage) }
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

    @Published var autoDetectSource: Bool {
        didSet { defaults.set(autoDetectSource, forKey: Keys.autoDetectSource) }
    }

    @Published var deeplIsPro: Bool {
        didSet { defaults.set(deeplIsPro, forKey: Keys.deeplIsPro) }
    }

    private init() {
        let rawTarget = defaults.string(forKey: Keys.targetLanguage) ?? "it"
        self.targetLanguage = Language(rawValue: rawTarget) ?? .italian
        self.activeBackendID = defaults.string(forKey: Keys.activeBackend) ?? "google-web"
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        self.autoDetectSource = defaults.object(forKey: Keys.autoDetectSource) as? Bool ?? true
        self.deeplIsPro = defaults.bool(forKey: Keys.deeplIsPro)
    }

    private enum Keys {
        static let targetLanguage = "targetLanguage"
        static let activeBackend = "activeBackend"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let autoDetectSource = "autoDetectSource"
        static let deeplIsPro = "deeplIsPro"
    }
}
