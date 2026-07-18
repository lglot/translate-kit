import ArgumentParser
import Foundation
import XCTest
@testable import TranslateKitCore
@testable import tkit

final class CLIContractTests: XCTestCase {
    func testPlainTranslationOutputContainsOnlyTranslationAndNewline() {
        let result = TranslationResult(
            sourceText: "Ciao",
            translatedText: "Hello",
            sourceLanguage: .italian,
            targetLanguage: .english,
            backend: "DeepL"
        )

        XCTAssertEqual(CLITranslationRenderer.plain(result), "Hello\n")
    }

    func testJSONTranslationOutputHasStableFields() throws {
        let result = TranslationResult(
            sourceText: "Ciao",
            translatedText: "Hello",
            sourceLanguage: .italian,
            targetLanguage: .english,
            backend: "DeepL"
        )

        let data = try CLITranslationRenderer.json(result, provider: .deepl)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["source_text"] as? String, "Ciao")
        XCTAssertEqual(object["translation"] as? String, "Hello")
        XCTAssertEqual(object["detected_source_language"] as? String, "it")
        XCTAssertEqual(object["target_language"] as? String, "en")
        XCTAssertEqual(object["provider"] as? String, "deepl")
        XCTAssertEqual(object["character_count"] as? Int, 4)
    }

    func testConfigurationEditorSetsAndUnsetsKnownKeys() throws {
        var configuration = TranslateKitConfiguration.default

        try ConfigurationEditor.set(
            "providers.libretranslate.endpoint",
            value: "https://translate.example.com",
            in: &configuration
        )
        XCTAssertEqual(
            try ConfigurationEditor.get("providers.libretranslate.endpoint", from: configuration),
            "https://translate.example.com"
        )

        try ConfigurationEditor.unset("providers.libretranslate.endpoint", in: &configuration)
        XCTAssertEqual(
            configuration.providers.libretranslate.endpoint,
            TranslateKitConfiguration.default.providers.libretranslate.endpoint
        )
    }

    func testConfigurationEditorRejectsSecretKeys() {
        var configuration = TranslateKitConfiguration.default

        XCTAssertThrowsError(try ConfigurationEditor.set(
            "providers.deepl.api_key",
            value: "must-not-be-stored",
            in: &configuration
        )) { error in
            XCTAssertEqual(error as? ConfigurationEditorError, .unknownKey("providers.deepl.api_key"))
        }
    }

    func testExitCodeClassifierMatchesCLIContract() {
        XCTAssertEqual(CLIExitCode.classify(ConfigurationError.missingFile("config.toml")), 3)
        XCTAssertEqual(CLIExitCode.classify(TranslationError.apiKeyMissing("DeepL")), 3)
        XCTAssertEqual(CLIExitCode.classify(TranslationError.rateLimited), 1)
        XCTAssertEqual(CLIExitCode.usage, 2)
    }

    func testJSONErrorOutputNeverIncludesSecretValues() throws {
        let data = try CLIErrorRenderer.json(
            message: "Authentication failed for DeepL.",
            code: 3
        )
        let rendered = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(rendered.contains("api_key"))
        XCTAssertFalse(rendered.contains("token"))
        XCTAssertTrue(rendered.contains("Authentication failed"))
    }

    func testParserDispositionDistinguishesHelpFromInvalidUsage() async {
        do {
            var command = try await TKitCommand.asyncParseAsRoot(["--help"])
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            XCTFail("Expected help parsing to stop command execution")
        } catch {
            XCTAssertEqual(CLIParserDisposition(error), .success)
        }

        do {
            _ = try await TKitCommand.asyncParseAsRoot(["unexpected"])
            XCTFail("Expected invalid usage to fail parsing")
        } catch {
            XCTAssertEqual(CLIParserDisposition(error), .usage)
        }
    }
}
