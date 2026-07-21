import Foundation

public struct TranslationResult: Sendable {
    public let sourceText: String
    public let translatedText: String
    public let sourceLanguage: Language
    public let targetLanguage: Language
    public let backend: String
    public let characterCount: Int

    public init(
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

public enum TranslationError: LocalizedError, Equatable, Sendable {
    case noInternet
    case apiError(String)
    case unsupportedLanguage(String)
    case invalidResponse
    case rateLimited
    case quotaExceeded(String)
    case authenticationFailed(String)
    case apiKeyMissing(String)
    case backendUnavailable(String)
    case modelNotDownloaded(Language, Language)
    case noTextSelected
    case secureInputActive
    case unsafeRedirect
    case invalidConfiguration(String)
    case cancelled

    public var errorDescription: String? {
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
        case .quotaExceeded(let backend):
            return "Quota exceeded for \(backend)."
        case .authenticationFailed(let backend):
            return "Authentication failed for \(backend)."
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
        case .unsafeRedirect:
            return "Translation request was redirected to an untrusted host."
        case .invalidConfiguration(let message):
            return "Invalid provider configuration: \(message)"
        case .cancelled:
            return "Translation was cancelled"
        }
    }
}
