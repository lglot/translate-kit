import Foundation

final class BackendManager: ObservableObject {
    static let shared = BackendManager()

    @Published var backends: [TranslationBackend] = []
    @Published var activeBackendID: String = "apple"

    private let preferences = PreferencesManager.shared

    var activeBackend: TranslationBackend {
        backends.first { $0.id == activeBackendID } ?? AppleBackend()
    }

    private init() {
        reload()
    }

    func reload() {
        var available: [TranslationBackend] = [AppleBackend()]

        if let key = KeychainHelper.get("deepl_api_key") {
            available.append(DeepLBackend(
                credential: .apiKey(key),
                configuration: .init(plan: preferences.deeplIsPro ? "pro" : "free")
            ))
        }

        if let key = KeychainHelper.get("google_cloud_api_key") {
            available.append(GoogleCloudBackend(credential: .apiKey(key)))
        }

        backends = available

        if available.contains(where: { $0.id == preferences.activeBackendID }) {
            activeBackendID = preferences.activeBackendID
        } else {
            activeBackendID = "apple"
            preferences.activeBackendID = "apple"
        }
    }

    func setActive(_ backend: TranslationBackend) {
        activeBackendID = backend.id
        preferences.activeBackendID = backend.id
    }
}
