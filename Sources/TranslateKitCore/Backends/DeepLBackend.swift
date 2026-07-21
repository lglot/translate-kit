import Foundation

public struct DeepLBackend: TranslationBackend {
    public let id = ProviderID.deepl.rawValue
    public let name = "DeepL"
    public let requiresAPIKey = true
    public var isAvailable: Bool { credential.isAPIKey }

    private let credential: ProviderCredential
    private let configuration: DeepLConfiguration
    private let httpClient: any HTTPClient

    public init(
        credential: ProviderCredential,
        configuration: DeepLConfiguration,
        httpClient: any HTTPClient = URLSessionHTTPClient.shared
    ) {
        self.credential = credential
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        guard case .apiKey(let apiKey) = credential else {
            throw TranslationError.apiKeyMissing(name)
        }
        let host = configuration.plan == "pro" ? "api.deepl.com" : "api-free.deepl.com"
        guard let url = URL(string: "https://\(host)/v2/translate") else {
            throw TranslationError.invalidConfiguration("DeepL endpoint")
        }

        var form = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "target_lang", value: target.rawValue.uppercased())
        ]
        if source != .auto {
            form.append(URLQueryItem(name: "source_lang", value: source.rawValue.uppercased()))
        }
        var body = URLComponents()
        body.queryItems = form

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")

        let response = try await perform(request, using: httpClient)
        try validateStatus(response, source: source, target: target)
        guard
            let decoded = try? JSONDecoder().decode(DeepLResponse.self, from: response.data),
            let translation = decoded.translations.first
        else {
            throw TranslationError.invalidResponse
        }
        let detected = source == .auto
            ? Language(rawValue: translation.detectedSourceLanguage.lowercased()) ?? .auto
            : source
        return TranslationResult(
            sourceText: text,
            translatedText: translation.text,
            sourceLanguage: detected,
            targetLanguage: target,
            backend: name
        )
    }

    private func validateStatus(_ response: HTTPResponse, source: Language, target: Language) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 400:
            if let message = try? JSONDecoder().decode(DeepLErrorResponse.self, from: response.data).message,
               message.describesUnsupportedLanguage {
                throw TranslationError.unsupportedLanguage("\(source.rawValue) to \(target.rawValue)")
            }
            throw TranslationError.apiError("DeepL rejected the request (HTTP 400)")
        case 401, 403:
            throw TranslationError.authenticationFailed(name)
        case 429:
            throw TranslationError.rateLimited
        case 456:
            throw TranslationError.quotaExceeded(name)
        default:
            throw TranslationError.apiError("DeepL rejected the request (HTTP \(response.statusCode))")
        }
    }
}

private struct DeepLErrorResponse: Decodable {
    let message: String
}

private struct DeepLResponse: Decodable {
    let translations: [DeepLTranslation]
}

private struct DeepLTranslation: Decodable {
    let detectedSourceLanguage: String
    let text: String

    private enum CodingKeys: String, CodingKey {
        case detectedSourceLanguage = "detected_source_language"
        case text
    }
}
