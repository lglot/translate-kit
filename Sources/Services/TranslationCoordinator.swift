import Foundation

/// Resolves the translation direction from the configured language pair and
/// dispatches to the active backend.
@MainActor
enum TranslationCoordinator {
    static func translate(_ text: String, targetOverride: Language? = nil) async throws -> TranslationResult {
        let pair = PreferencesManager.shared.languagePair
        var (source, target) = pair.direction(for: text)
        if let override = targetOverride {
            target = override
            if source == override {
                // user forced the target to the detected source: let the backend re-detect
                source = .auto
            }
        }
        return try await BackendManager.shared.activeBackend.translate(text, from: source, to: target)
    }
}
