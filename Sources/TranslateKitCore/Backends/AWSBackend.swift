import Foundation

public struct AmazonTranslateRequest: Equatable, Sendable {
    public let text: String
    public let sourceLanguageCode: String
    public let targetLanguageCode: String

    public init(text: String, sourceLanguageCode: String, targetLanguageCode: String) {
        self.text = text
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
    }
}

public struct AmazonTranslateResponse: Equatable, Sendable {
    public let translatedText: String
    public let sourceLanguageCode: String?
    public let targetLanguageCode: String?

    public init(
        translatedText: String,
        sourceLanguageCode: String?,
        targetLanguageCode: String?
    ) {
        self.translatedText = translatedText
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
    }
}

public protocol AmazonTranslateClient: Sendable {
    func translate(_ request: AmazonTranslateRequest) async throws -> AmazonTranslateResponse
}

public enum AmazonTranslateClientError: Error, Equatable, Sendable {
    case authentication
    case quota
    case rateLimited
    case unsupportedLanguage
    case invalidResponse
    case network
    case service
}

public struct AWSBackend: TranslationBackend {
    public let id = ProviderID.aws.rawValue
    public let name = "Amazon Translate"
    public let requiresAPIKey = false
    public let isAvailable = true

    private let client: any AmazonTranslateClient

    public init(client: any AmazonTranslateClient) {
        self.client = client
    }

    public func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        let request = AmazonTranslateRequest(
            text: text,
            sourceLanguageCode: source.rawValue,
            targetLanguageCode: target.rawValue
        )

        let response: AmazonTranslateResponse
        do {
            response = try await client.translate(request)
        } catch let error as AmazonTranslateClientError {
            throw map(error, source: source, target: target)
        } catch {
            throw TranslationError.apiError("Amazon Translate request failed")
        }

        let detected = source == .auto
            ? response.sourceLanguageCode.flatMap(Language.init(rawValue:)) ?? .auto
            : source
        return TranslationResult(
            sourceText: text,
            translatedText: response.translatedText,
            sourceLanguage: detected,
            targetLanguage: target,
            backend: name
        )
    }

    private func map(
        _ error: AmazonTranslateClientError,
        source: Language,
        target: Language
    ) -> TranslationError {
        switch error {
        case .authentication:
            return .authenticationFailed(name)
        case .quota:
            return .quotaExceeded(name)
        case .rateLimited:
            return .rateLimited
        case .unsupportedLanguage:
            return .unsupportedLanguage("\(source.rawValue) to \(target.rawValue)")
        case .invalidResponse:
            return .invalidResponse
        case .network:
            return .noInternet
        case .service:
            return .apiError("Amazon Translate request failed")
        }
    }
}
