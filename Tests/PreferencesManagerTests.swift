import Foundation
import XCTest
@testable import TranslateKit
@testable import TranslateKitCore

@MainActor
final class PreferencesManagerTests: XCTestCase {
    func testMissingConfigurationMigratesLegacyTranslationPreferences() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set("fr", forKey: "firstLanguage")
        fixture.defaults.set("de", forKey: "secondLanguage")
        fixture.defaults.set("deepl", forKey: "activeBackend")
        fixture.defaults.set(true, forKey: "deeplIsPro")

        let manager = PreferencesManager(
            defaults: fixture.defaults,
            configurationStore: fixture.store
        )

        XCTAssertEqual(manager.firstLanguage, .french)
        XCTAssertEqual(manager.secondLanguage, .german)
        XCTAssertEqual(manager.activeBackendID, "deepl")
        XCTAssertTrue(manager.deeplIsPro)
        XCTAssertTrue(fixture.defaults.bool(forKey: "configurationMigrationCompleted"))
        XCTAssertEqual(try fixture.store.load().translation.provider, "deepl")
    }

    func testTranslationChangesPersistToTOMLInsteadOfLegacyDefaults() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let manager = PreferencesManager(
            defaults: fixture.defaults,
            configurationStore: fixture.store
        )

        manager.activeBackendID = "azure"
        manager.azureRegion = "westeurope"

        let stored = try fixture.store.load()
        XCTAssertEqual(stored.translation.provider, "azure")
        XCTAssertEqual(stored.providers.azure.region, "westeurope")
        XCTAssertNil(fixture.defaults.string(forKey: "activeBackend"))
    }

    func testInvalidExistingTOMLIsReportedAndNotOverwritten() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.store.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let invalid = Data("version = 99\n".utf8)
        try invalid.write(to: fixture.store.url)

        let manager = PreferencesManager(
            defaults: fixture.defaults,
            configurationStore: fixture.store
        )
        manager.firstLanguage = .french

        XCTAssertNotNil(manager.configurationError)
        XCTAssertEqual(try Data(contentsOf: fixture.store.url), invalid)
    }

    func testBackendManagerKeepsEveryProviderVisibleWithoutCredentials() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let preferences = PreferencesManager(
            defaults: fixture.defaults,
            configurationStore: fixture.store
        )
        let registry = ProviderRegistry(credentialResolver: NoCredentialsResolver())
        let manager = BackendManager(preferences: preferences, registry: registry)

        await manager.reload()

        XCTAssertEqual(
            manager.providers.map(\.descriptor.id),
            [.apple, .deepl, .googleCloud, .azure, .aws, .libretranslate]
        )
        manager.setActive(.azure)
        XCTAssertEqual(manager.activeBackendID, "azure")
        XCTAssertEqual(try fixture.store.load().translation.provider, "azure")
    }

    private func makeFixture() throws -> Fixture {
        let identifier = "TranslateKit.PreferencesManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: identifier))
        defaults.removePersistentDomain(forName: identifier)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-preferences-tests-\(UUID().uuidString)", isDirectory: true)
        return Fixture(
            defaults: defaults,
            defaultsIdentifier: identifier,
            directory: directory,
            store: ConfigurationStore(url: directory.appendingPathComponent("config.toml"))
        )
    }
}

private struct NoCredentialsResolver: CredentialResolving {
    func resolve(
        for provider: ProviderID,
        configuration: TranslateKitConfiguration
    ) async throws -> ProviderCredential {
        .none
    }

    func discover(provider: ProviderID) async throws -> CredentialDiscovery {
        CredentialDiscovery(provider: provider, isAvailable: false, sources: [.none])
    }
}

private struct Fixture {
    let defaults: UserDefaults
    let defaultsIdentifier: String
    let directory: URL
    let store: ConfigurationStore

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsIdentifier)
        try? FileManager.default.removeItem(at: directory)
    }
}
