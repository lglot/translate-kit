import Foundation

public struct GoogleCloudBackend: TranslationBackend {
    public let id = ProviderID.googleCloud.rawValue
    public let name = "Google Cloud"
    public let requiresAPIKey: Bool
    public var isAvailable: Bool { credential.isAPIKey || credential.isBearerToken }

    private let credential: ProviderCredential
    private let httpClient: any HTTPClient

    public init(
        credential: ProviderCredential,
        httpClient: any HTTPClient = URLSessionHTTPClient.shared
    ) {
        self.credential = credential
        self.httpClient = httpClient
        requiresAPIKey = !credential.isBearerToken
    }

    public func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        let components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        guard credential.isAPIKey || credential.isBearerToken else {
            throw TranslationError.apiKeyMissing(name)
        }
        guard let url = components.url else {
            throw TranslationError.invalidConfiguration("Google Cloud endpoint")
        }

        var payload: [String: String] = [
            "q": text,
            "target": target.rawValue,
            "format": "text"
        ]
        if source != .auto { payload["source"] = source.rawValue }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if case .apiKey(let key) = credential {
            request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        } else if case .bearerToken(let token, let quotaProject) = credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let quotaProject, !quotaProject.isEmpty {
                request.setValue(quotaProject, forHTTPHeaderField: "X-Goog-User-Project")
            }
        }

        let response = try await perform(request, using: httpClient)
        try validateStatus(response, source: source, target: target)
        guard
            let decoded = try? JSONDecoder().decode(GoogleCloudResponse.self, from: response.data),
            let translation = decoded.data.translations.first
        else {
            throw TranslationError.invalidResponse
        }
        let detected = source == .auto
            ? translation.detectedSourceLanguage.flatMap(Language.init(rawValue:)) ?? .auto
            : source
        return TranslationResult(
            sourceText: text,
            translatedText: translation.translatedText,
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
                GoogleCloudErrorResponse.self,
                from: response.data
            ).error.message, message.describesUnsupportedLanguage {
                throw TranslationError.unsupportedLanguage("\(source.rawValue) to \(target.rawValue)")
            }
            throw TranslationError.apiError("Google Cloud rejected the request (HTTP 400)")
        case 401, 403:
            throw TranslationError.authenticationFailed(name)
        case 429:
            throw TranslationError.quotaExceeded(name)
        default:
            throw TranslationError.apiError(
                "Google Cloud rejected the request (HTTP \(response.statusCode))"
            )
        }
    }
}

private struct GoogleCloudErrorResponse: Decodable {
    let error: GoogleCloudErrorDetail
}

private struct GoogleCloudErrorDetail: Decodable {
    let message: String
}

private struct GoogleCloudResponse: Decodable {
    let data: GoogleCloudData
}

private struct GoogleCloudData: Decodable {
    let translations: [GoogleCloudTranslation]
}

private struct GoogleCloudTranslation: Decodable {
    let translatedText: String
    let detectedSourceLanguage: String?
}
