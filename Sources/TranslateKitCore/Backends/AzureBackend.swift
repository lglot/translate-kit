import Foundation

public struct AzureBackend: TranslationBackend {
    public let id = ProviderID.azure.rawValue
    public let name = "Azure Translator"
    public let requiresAPIKey: Bool
    public var isAvailable: Bool { credential.isAPIKey || credential.isBearerToken }

    private let credential: ProviderCredential
    private let configuration: AzureConfiguration
    private let httpClient: any HTTPClient

    public init(
        credential: ProviderCredential,
        configuration: AzureConfiguration,
        httpClient: any HTTPClient = URLSessionHTTPClient.shared
    ) {
        self.credential = credential
        self.configuration = configuration
        self.httpClient = httpClient
        requiresAPIKey = !credential.isBearerToken
    }

    public func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        guard var components = URLComponents(string: configuration.endpoint) else {
            throw TranslationError.invalidConfiguration("Azure endpoint")
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = TranslateKitConfiguration.isAzureCustomEndpoint(configuration.endpoint)
                ? "/translator/text/v3.0/translate"
                : "/translate"
        } else if !components.path.hasSuffix("/translate") {
            components.path += "/translate"
        }
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: target.rawValue)
        ]
        if source != .auto {
            components.queryItems?.append(URLQueryItem(name: "from", value: source.rawValue))
        }
        guard let url = components.url else {
            throw TranslationError.invalidConfiguration("Azure endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode([AzureRequest(text: text)])
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        switch credential {
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        case .bearerToken(let token, _):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        default:
            throw TranslationError.apiKeyMissing(name)
        }
        if !configuration.region.isEmpty {
            request.setValue(configuration.region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }

        let response = try await perform(request, using: httpClient)
        try validateStatus(response, source: source, target: target)
        guard
            let decoded = try? JSONDecoder().decode([AzureResponse].self, from: response.data),
            let first = decoded.first,
            let translation = first.translations.first
        else {
            throw TranslationError.invalidResponse
        }
        let detected = source == .auto
            ? first.detectedLanguage.flatMap { Language(rawValue: $0.language) } ?? .auto
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
            let languageErrorCodes: Set<Int> = [400003, 400019, 400023, 400035, 400036]
            if let code = try? JSONDecoder().decode(AzureErrorResponse.self, from: response.data).error.code,
               languageErrorCodes.contains(code) {
                throw TranslationError.unsupportedLanguage("\(source.rawValue) to \(target.rawValue)")
            }
            throw TranslationError.apiError("Azure Translator rejected the request (HTTP 400)")
        case 401, 403:
            throw TranslationError.authenticationFailed(name)
        case 429:
            throw TranslationError.rateLimited
        default:
            throw TranslationError.apiError(
                "Azure Translator rejected the request (HTTP \(response.statusCode))"
            )
        }
    }
}

private struct AzureErrorResponse: Decodable {
    let error: AzureErrorDetail
}

private struct AzureErrorDetail: Decodable {
    let code: Int
}

private struct AzureRequest: Encodable {
    let text: String

    private enum CodingKeys: String, CodingKey {
        case text = "Text"
    }
}

private struct AzureResponse: Decodable {
    let detectedLanguage: AzureDetectedLanguage?
    let translations: [AzureTranslation]
}

private struct AzureDetectedLanguage: Decodable {
    let language: String
}

private struct AzureTranslation: Decodable {
    let text: String
}
