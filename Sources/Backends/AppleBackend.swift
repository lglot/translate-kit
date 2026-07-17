import Foundation

struct AppleBackend: TranslationBackend {
    let id = "apple"
    let name = "Apple (On-Device)"
    let requiresAPIKey = false
    var isAvailable: Bool { true }

    func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        let effectiveSource: Language? = source == .auto ? nil : source
        let translated = try await AppleTranslationProvider.shared.translate(
            text, from: effectiveSource, to: target)
        return TranslationResult(
            sourceText: text,
            translatedText: translated,
            sourceLanguage: source,
            targetLanguage: target,
            backend: name
        )
    }
}
