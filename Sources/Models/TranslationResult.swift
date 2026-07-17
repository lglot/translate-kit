import Foundation

struct TranslationResult: Sendable {
    let sourceText: String
    let translatedText: String
    let sourceLanguage: Language
    let targetLanguage: Language
    let backend: String
    let characterCount: Int

    init(
        sourceText: String,
        translatedText: String,
        sourceLanguage: Language,
        targetLanguage: Language,
        backend: String
    ) {
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.backend = backend
        self.characterCount = sourceText.count
    }
}

enum TranslationError: LocalizedError {
    case noInternet
    case apiError(String)
    case unsupportedLanguage(String)
    case invalidResponse
    case rateLimited
    case apiKeyMissing(String)
    case backendUnavailable(String)
    case modelNotDownloaded(Language, Language)
    case noTextSelected
    case secureInputActive

    var errorDescription: String? {
        switch self {
        case .noInternet:
            return "No internet connection"
        case .apiError(let message):
            return "API error: \(message)"
        case .unsupportedLanguage(let lang):
            return "Unsupported language: \(lang)"
        case .invalidResponse:
            return "Invalid response from translation service"
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .apiKeyMissing(let backend):
            return "API key not configured for \(backend). Add it in Settings."
        case .backendUnavailable(let backend):
            return "\(backend) is not available on this system."
        case .modelNotDownloaded(let source, let target):
            return "Language pack \(source.displayName) to \(target.displayName) is not downloaded. Open Settings > Languages to download it."
        case .noTextSelected:
            return "No text selected"
        case .secureInputActive:
            return "A secure input field is active. Translation is disabled for passwords."
        }
    }
}
