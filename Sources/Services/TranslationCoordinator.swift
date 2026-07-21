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
            return try await service.translate(
                TranslationRequest(text: text, target: targetOverride),
                configuration: configuration
            )
        }

        return try await service.translate(
            TranslationRequest(text: text),
            configuration: configuration
        )
    }
}
