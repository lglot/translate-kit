import Foundation

public struct LibreTranslateBackend: TranslationBackend {
    public let id = ProviderID.libretranslate.rawValue
    public let name = "LibreTranslate"
    public let requiresAPIKey = false
    public var isAvailable: Bool { true }

    private let credential: ProviderCredential
    private let configuration: LibreTranslateConfiguration
    private let httpClient: any HTTPClient

    public init(
        credential: ProviderCredential = .none,
        configuration: LibreTranslateConfiguration,
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
        guard var components = URLComponents(string: configuration.endpoint) else {
            throw TranslationError.invalidConfiguration("LibreTranslate endpoint")
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/translate"
        } else if !components.path.hasSuffix("/translate") {
            components.path += "/translate"
        }
        guard let url = components.url else {
            throw TranslationError.invalidConfiguration("LibreTranslate endpoint")
        }

        var payload: [String: String] = [
            "q": text,
            "source": source.rawValue,
            "target": target.rawValue,
            "format": "text"
        ]
        let key: String?
        if case .apiKey(let apiKey) = credential {
            payload["api_key"] = apiKey
            key = apiKey
        } else {
            key = nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let response = try await perform(request, using: httpClient)
        if key != nil, response.url.host?.lowercased() != url.host?.lowercased() {
            throw TranslationError.unsafeRedirect
        }
        try validateStatus(response, source: source, target: target)
        guard let decoded = try? JSONDecoder().decode(LibreTranslateResponse.self, from: response.data) else {
            throw TranslationError.invalidResponse
        }
        let detected = source == .auto
            ? decoded.detectedLanguage.flatMap { Language(rawValue: $0.language) } ?? .auto
            : source
        return TranslationResult(
            sourceText: text,
            translatedText: decoded.translatedText,
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
            if let message = try? JSONDecoder().decode(
                LibreTranslateErrorResponse.self,
                from: response.data
            ).error,
               message.describesLibreTranslateUnsupportedLanguage(
                   sourceCode: source.rawValue,
                   targetCode: target.rawValue
               ) {
                throw TranslationError.unsupportedLanguage("\(source.rawValue) to \(target.rawValue)")
            }
            throw TranslationError.apiError("LibreTranslate rejected the request (HTTP 400)")
        case 401, 403:
            throw TranslationError.authenticationFailed(name)
        case 429:
            throw TranslationError.rateLimited
        default:
            throw TranslationError.apiError(
                "LibreTranslate rejected the request (HTTP \(response.statusCode))"
            )
        }
    }
}

private struct LibreTranslateErrorResponse: Decodable {
    let error: String
}

private struct LibreTranslateResponse: Decodable {
    let translatedText: String
    let detectedLanguage: LibreDetectedLanguage?
}

private struct LibreDetectedLanguage: Decodable {
    let language: String
}
