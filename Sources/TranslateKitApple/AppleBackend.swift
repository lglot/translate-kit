import Foundation
import TranslateKitCore

public struct AppleBackend: TranslationBackend {
    public let id = "apple"
    public let name = "Apple (On-Device)"
    public let requiresAPIKey = false
    public var isAvailable: Bool { true }

    public init() {}

    public func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        let effectiveSource: Language? = source == .auto ? nil : source
        let output = try await AppleTranslationProvider.shared.translate(
            text, from: effectiveSource, to: target)
        return TranslationResult(
            sourceText: text,
            translatedText: output.text,
            sourceLanguage: output.sourceLanguage,
            targetLanguage: target,
            backend: name
        )
    }
}
