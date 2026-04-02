import Foundation

struct GoogleWebBackend: TranslationBackend {
    let id = "google-web"
    let name = "Google Translate"
    let requiresAPIKey = false
    var isAvailable: Bool { true }

    func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source == .auto ? "auto" : source.rawValue),
            URLQueryItem(name: "tl", value: target.rawValue),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200: break
        case 429: throw TranslationError.rateLimited
        default: throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let translated = try parseGoogleResponse(data, originalText: text)
        let detectedSource: Language = {
            if source == .auto, let detected = try? extractDetectedLanguage(from: data) {
                return Language(rawValue: detected) ?? source
            }
            return source
        }()

        return TranslationResult(
            sourceText: text,
            translatedText: translated,
            sourceLanguage: detectedSource,
            targetLanguage: target,
            backend: name
        )
    }

    private func parseGoogleResponse(_ data: Data, originalText: String) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = json[0] as? [Any] else {
            throw TranslationError.invalidResponse
        }

        var result = ""
        for sentence in sentences {
            if let parts = sentence as? [Any], let segment = parts[0] as? String {
                result += segment
            }
        }

        if result.isEmpty {
            throw TranslationError.invalidResponse
        }

        return result
    }

    private func extractDetectedLanguage(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              let detectedLang = json[2] as? String else {
            return "auto"
        }
        return detectedLang
    }
}
