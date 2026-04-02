import Foundation

struct GoogleCloudBackend: TranslationBackend {
    let id = "google-cloud"
    let name = "Google Cloud"
    let requiresAPIKey = true
    var isAvailable: Bool { KeychainHelper.get("google_cloud_api_key") != nil }

    func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        guard let apiKey = KeychainHelper.get("google_cloud_api_key") else {
            throw TranslationError.apiKeyMissing(name)
        }

        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "target", value: target.rawValue),
            URLQueryItem(name: "format", value: "text")
        ]
        if source != .auto {
            components.queryItems?.append(
                URLQueryItem(name: "source", value: source.rawValue)
            )
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200: break
        case 400: throw TranslationError.apiError("Invalid request")
        case 403: throw TranslationError.apiError("Invalid Google Cloud API key")
        case 429: throw TranslationError.rateLimited
        default: throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(GoogleCloudResponse.self, from: data)
        guard let translation = decoded.data.translations.first else {
            throw TranslationError.invalidResponse
        }

        let detectedSource: Language = {
            if source == .auto {
                return Language(rawValue: translation.detectedSourceLanguage ?? "") ?? source
            }
            return source
        }()

        return TranslationResult(
            sourceText: text,
            translatedText: translation.translatedText,
            sourceLanguage: detectedSource,
            targetLanguage: target,
            backend: name
        )
    }
}

private struct GoogleCloudResponse: Codable {
    let data: GoogleCloudData
}

private struct GoogleCloudData: Codable {
    let translations: [GoogleCloudTranslation]
}

private struct GoogleCloudTranslation: Codable {
    let translatedText: String
    let detectedSourceLanguage: String?
}
