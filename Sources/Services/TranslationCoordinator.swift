import Foundation
import TranslateKitApple
import TranslateKitCore

/// Resolves direction from the shared TOML configuration and dispatches through
/// the same provider registry used by the CLI.
@MainActor
enum TranslationCoordinator {
    private static let service = TranslationService(
        backendResolver: ProviderRegistry(appleBackendFactory: { AppleBackend() })
    )

    static func translate(
        _ text: String,
        targetOverride: Language? = nil
    ) async throws -> TranslationResult {
        let preferences = PreferencesManager.shared
        let configuration = try preferences.validatedConfiguration()

        if let targetOverride {
            var (source, target) = preferences.languagePair.direction(for: text)
            target = targetOverride
            if source == targetOverride { source = .auto }
            return try await service.translate(
                TranslationRequest(text: text, source: source, target: target),
                configuration: configuration
            )
        }

        return try await service.translate(
            TranslationRequest(text: text),
            configuration: configuration
        )
    }
}
