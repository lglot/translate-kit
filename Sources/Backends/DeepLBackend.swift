import Foundation

struct DeepLBackend: TranslationBackend {
    let id = "deepl"
    let name = "DeepL"
    let requiresAPIKey = true
    var isAvailable: Bool { KeychainHelper.get("deepl_api_key") != nil }

    func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        guard let apiKey = KeychainHelper.get("deepl_api_key") else {
            throw TranslationError.apiKeyMissing(name)
        }

        let isPro = UserDefaults.standard.bool(forKey: "deepl_is_pro")
        let baseURL = isPro
            ? "https://api.deepl.com/v2/translate"
            : "https://api-free.deepl.com/v2/translate"

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "auth_key", value: apiKey),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "target_lang", value: target.rawValue.uppercased())
        ]
        if source != .auto {
            bodyComponents.queryItems?.append(
                URLQueryItem(name: "source_lang", value: source.rawValue.uppercased())
            )
        }

        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200: break
        case 403: throw TranslationError.apiError("Invalid DeepL API key")
        case 429: throw TranslationError.rateLimited
        case 456: throw TranslationError.rateLimited
        default: throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)
        guard let translation = decoded.translations.first else {
            throw TranslationError.invalidResponse
        }

        let detectedSource: Language = {
            if source == .auto {
                return Language(rawValue: translation.detectedSourceLanguage.lowercased()) ?? source
            }
            return source
        }()

        return TranslationResult(
            sourceText: text,
            translatedText: translation.text,
            sourceLanguage: detectedSource,
            targetLanguage: target,
            backend: name
        )
    }
}

private struct DeepLResponse: Codable {
    let translations: [DeepLTranslation]
}

private struct DeepLTranslation: Codable {
    let detectedSourceLanguage: String
    let text: String
}
