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

    func testWritesUserOnlyPermissions() throws {
        let store = ConfigurationStore(url: configurationURL)
        try store.save(.default)

        let attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }
}
