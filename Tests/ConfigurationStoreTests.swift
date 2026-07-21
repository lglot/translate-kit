import Foundation
import XCTest
@testable import TranslateKitCore

final class ConfigurationStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var configurationURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-config-tests-\(UUID().uuidString)", isDirectory: true)
        configurationURL = temporaryDirectory.appendingPathComponent("config.toml")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testDefaultConfigurationMatchesProductDefaults() {
        let configuration = TranslateKitConfiguration.default

        XCTAssertEqual(configuration.version, 1)
        XCTAssertEqual(configuration.translation.provider, "apple")
        XCTAssertEqual(configuration.translation.firstLanguage, "it")
        XCTAssertEqual(configuration.translation.secondLanguage, "en")
        XCTAssertEqual(configuration.providers.deepl.plan, "free")
    }

    func testRoundTripsConfigurationThroughTOML() throws {
        let store = ConfigurationStore(url: configurationURL)
        var configuration = TranslateKitConfiguration.default
        configuration.translation.provider = "libretranslate"
        configuration.providers.libretranslate.endpoint = "http://127.0.0.1:5000"

        try store.save(configuration)
        let loaded = try store.load()

        XCTAssertEqual(loaded, configuration)
    }

    func testLoadDoesNotRewriteExistingFile() throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let source = """
        # Keep this comment.
        version = 1

        [translation]
        provider = "apple"
        first_language = "it"
        second_language = "en"
        """
        try source.data(using: .utf8)!.write(to: configurationURL)
        let store = ConfigurationStore(url: configurationURL)

        _ = try store.load()

        XCTAssertEqual(try String(contentsOf: configurationURL, encoding: .utf8), source)
    }

    func testUnknownKeyIsRejected() throws {
        let source = """
        version = 1
        unknown = true
        """
        let store = ConfigurationStore(url: configurationURL)

        XCTAssertThrowsError(try store.decode(source)) { error in
            XCTAssertTrue(error.localizedDescription.contains("unknown"))
        }
    }

    func testUnknownNestedKeyIsRejected() {
        let source = """
        [providers.azure]
        endpoint = "https://api.cognitive.microsofttranslator.com"
        unexpected = "value"
        """
        let store = ConfigurationStore(url: configurationURL)

        XCTAssertThrowsError(try store.decode(source)) { error in
            XCTAssertTrue(error.localizedDescription.contains("providers.azure.unexpected"))
        }
    }

    func testAcceptsValidTOMLCommentsOnTableHeadersAndQuotedKeys() throws {
        let source = """
        "version" = 1

        [translation] # preferred pair
        provider = "apple"
        first_language = "it"
        second_language = "en"
        """
        let store = ConfigurationStore(url: configurationURL)

        let configuration = try store.decode(source)

        XCTAssertEqual(configuration.translation.provider, "apple")
        XCTAssertEqual(configuration.translation.firstLanguage, "it")
        XCTAssertEqual(configuration.translation.secondLanguage, "en")
    }

    func testMigrationCreatesMissingFileFromLegacyValues() throws {
        let store = ConfigurationStore(url: configurationURL)
        let legacy = LegacyTranslationPreferences(
            provider: "deepl",
            firstLanguage: "fr",
            secondLanguage: "de",
            deeplPlan: "pro"
        )

        let configuration = try store.loadOrCreate(legacy: legacy)

        XCTAssertEqual(configuration.translation.provider, "deepl")
        XCTAssertEqual(configuration.translation.firstLanguage, "fr")
        XCTAssertEqual(configuration.translation.secondLanguage, "de")
        XCTAssertEqual(configuration.providers.deepl.plan, "pro")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configurationURL.path))
    }

    func testExistingFileWinsOverLegacyValues() throws {
        let store = ConfigurationStore(url: configurationURL)
        var existing = TranslateKitConfiguration.default
        existing.translation.firstLanguage = "es"
        try store.save(existing)

        let loaded = try store.loadOrCreate(
            legacy: LegacyTranslationPreferences(
                provider: "deepl",
                firstLanguage: "fr",
                secondLanguage: "de",
                deeplPlan: "pro"
            )
        )

        XCTAssertEqual(loaded, existing)
    }

    func testRejectsRemotePlainHTTPLibreTranslateEndpoint() {
        var configuration = TranslateKitConfiguration.default
        configuration.providers.libretranslate.endpoint = "http://translate.example.com"

        XCTAssertThrowsError(try configuration.validate())
    }

    func testRejectsLibreTranslateEndpointWithEmbeddedCredentials() {
        var configuration = TranslateKitConfiguration.default
        configuration.providers.libretranslate.endpoint =
            "https://user:password@translate.example.com"

        XCTAssertThrowsError(try configuration.validate())
    }

    func testRejectsNonAzureHTTPSAzureEndpoint() {
        var configuration = TranslateKitConfiguration.default
        configuration.providers.azure.endpoint = "https://collector.example"

        XCTAssertThrowsError(try configuration.validate())
    }

    func testAcceptsOfficialAzureTranslatorEndpoints() throws {
        let endpoints = [
            "https://api.cognitive.microsofttranslator.com",
            "https://api-eur.cognitive.microsofttranslator.com",
            "https://translator-resource.cognitiveservices.azure.com",
            "https://api.cognitive.microsofttranslator.us",
            "https://translator-resource.cognitiveservices.azure.us",
            "https://api.translator.azure.cn",
            "https://translator-resource.cognitiveservices.azure.cn"
        ]

        for endpoint in endpoints {
            var configuration = TranslateKitConfiguration.default
            configuration.providers.azure.endpoint = endpoint
            XCTAssertNoThrow(try configuration.validate(), endpoint)
        }
    }

    func testRejectsAzureEndpointWithUserInfoOrNonStandardPort() {
        for endpoint in [
            "https://user@api.cognitive.microsofttranslator.com",
            "https://api.cognitive.microsofttranslator.com:8443"
        ] {
            var configuration = TranslateKitConfiguration.default
            configuration.providers.azure.endpoint = endpoint
            XCTAssertThrowsError(try configuration.validate(), endpoint)
        }
    }

    func testAzureEntraRequiresCustomDomainEndpoint() {
        var configuration = TranslateKitConfiguration.default
        configuration.providers.azure.auth = "entra"

        XCTAssertThrowsError(try configuration.validate())

        configuration.providers.azure.endpoint =
            "https://translator-resource.cognitiveservices.azure.com"
        XCTAssertNoThrow(try configuration.validate())

        configuration.providers.azure.endpoint =
            "https://translator-resource.cognitiveservices.azure.us"
        XCTAssertThrowsError(try configuration.validate())
    }

    func testWritesUserOnlyPermissions() throws {
        let store = ConfigurationStore(url: configurationURL)
        try store.save(.default)

        let attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testPreservesExistingConfigurationDirectoryPermissions() throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let store = ConfigurationStore(url: configurationURL)

        try store.save(.default)

        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryDirectory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o755)
    }
}
