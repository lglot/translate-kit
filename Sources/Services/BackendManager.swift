import Foundation

final class BackendManager: ObservableObject {
    static let shared = BackendManager()

    @Published var backends: [TranslationBackend] = []
    @Published var activeBackendID: String = "google-web"

    private let preferences = PreferencesManager.shared

    var activeBackend: TranslationBackend {
        backends.first { $0.id == activeBackendID } ?? (backends.first ?? GoogleWebBackend())
    }

    private init() {
        reload()
    }

    func reload() {
        var available: [TranslationBackend] = []

        // Google Web (always available, free)
        available.append(GoogleWebBackend())

        // Apple (macOS 15+)
        if #available(macOS 15.0, *) {
            available.append(AppleBackend())
        }

        // DeepL (if API key configured)
        if KeychainHelper.get("deepl_api_key") != nil {
            available.append(DeepLBackend())
        }

        // Google Cloud (if API key configured)
        if KeychainHelper.get("google_cloud_api_key") != nil {
            available.append(GoogleCloudBackend())
        }

        backends = available

        if !available.contains(where: { $0.id == activeBackendID }) {
            activeBackendID = "google-web"
            preferences.activeBackendID = "google-web"
        } else {
            activeBackendID = preferences.activeBackendID
        }
    }

    func setActive(_ backend: TranslationBackend) {
        activeBackendID = backend.id
        preferences.activeBackendID = backend.id
    }
}
