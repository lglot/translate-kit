import Foundation
import TranslateKitCore

enum CLITranslationRenderer {
    static func plain(_ result: TranslationResult) -> String {
        result.translatedText + "\n"
    }

    static func json(_ result: TranslationResult, provider: ProviderID) throws -> Data {
        try encoder.encode(JSONTranslation(
            sourceText: result.sourceText,
            translation: result.translatedText,
            detectedSourceLanguage: result.sourceLanguage.rawValue,
            targetLanguage: result.targetLanguage.rawValue,
            provider: provider.rawValue,
            characterCount: result.characterCount
        ))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private struct JSONTranslation: Encodable {
    let sourceText: String
    let translation: String
    let detectedSourceLanguage: String
    let targetLanguage: String
    let provider: String
    let characterCount: Int

    private enum CodingKeys: String, CodingKey {
        case sourceText = "source_text"
        case translation
        case detectedSourceLanguage = "detected_source_language"
        case targetLanguage = "target_language"
        case provider
        case characterCount = "character_count"
    }
}

enum CLIErrorRenderer {
    static func json(message: String, code: Int32) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JSONError(error: message, exitCode: code))
    }
}

private struct JSONError: Encodable {
    let error: String
    let exitCode: Int32

    private enum CodingKeys: String, CodingKey {
        case error
        case exitCode = "exit_code"
    }
}

enum CLIExitCode {
    static let usage: Int32 = 2
    static let configuration: Int32 = 3
    static let translation: Int32 = 1

    static func classify(_ error: Error) -> Int32 {
        if let error = error as? CLIReportedError { return error.code }
        if error is ConfigurationError
            || error is ConfigurationEditorError
            || error is CredentialResolverError
            || error is SecretStoreError {
            return configuration
        }
        if error is TranslationDirectionError || error is CLIInputError {
            return usage
        }
        if let error = error as? TranslationError {
            switch error {
            case .apiKeyMissing, .authenticationFailed, .invalidConfiguration:
                return configuration
            default:
                return translation
            }
        }
        return translation
    }
}

struct CLIReportedError: LocalizedError {
    let message: String
    let code: Int32
    let json: Bool

    init(_ error: Error, json: Bool) {
        message = error.localizedDescription
        code = CLIExitCode.classify(error)
        self.json = json
    }

    var errorDescription: String? { message }
}
