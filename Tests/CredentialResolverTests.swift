import Foundation
import XCTest
@testable import TranslateKitCore

final class CredentialResolverTests: XCTestCase {
    func testTranslateKitKeychainWinsOverEnvironment() async throws {
        let store = MemorySecretStore(values: [
            SecretReference.translateKit(.deepl): "saved-secret"
        ])
        let resolver = CredentialResolver(
            secretStore: store,
            environment: ["DEEPL_AUTH_KEY": "environment-secret"],
            processRunner: StubProcessRunner()
        )

        let credential = try await resolver.resolve(for: .deepl)

        XCTAssertEqual(credential, .apiKey("saved-secret"))
    }

    func testEnvironmentIsUsedWhenTranslateKitKeychainIsEmpty() async throws {
        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: ["GOOGLE_API_KEY": "environment-secret"],
            processRunner: StubProcessRunner()
        )

        let credential = try await resolver.resolve(for: .googleCloud)

        XCTAssertEqual(credential, .apiKey("environment-secret"))
    }

    func testAllowlistedDeepLKeyringItemIsUsedReadOnly() async throws {
        let store = MemorySecretStore(values: [
            SecretReference(service: "deepl", account: "DEEPL_AUTH_KEY"): "external-secret"
        ])
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: StubProcessRunner()
        )

        let credential = try await resolver.resolve(for: .deepl)

        XCTAssertEqual(credential, .apiKey("external-secret"))
        XCTAssertTrue(store.writes.isEmpty)
    }

    func testGoogleCLITokenIsUsedWithoutPersistingIt() async throws {
        let store = MemorySecretStore()
        let runner = StubProcessRunner(results: [
            "gcloud auth application-default print-access-token": "short-lived-token\n"
        ])
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: runner
        )

        let credential = try await resolver.resolve(for: .googleCloud)

        XCTAssertEqual(credential, .bearerToken("short-lived-token"))
        XCTAssertTrue(store.writes.isEmpty)
    }

    func testDiscoveryNeverContainsSecretValues() async throws {
        let store = MemorySecretStore(values: [
            SecretReference.translateKit(.deepl): "do-not-render-this-secret"
        ])
        let resolver = CredentialResolver(
            secretStore: store,
            environment: ["DEEPL_AUTH_KEY": "nor-this-one"],
            processRunner: StubProcessRunner()
        )

        let discovery = try await resolver.discover(provider: .deepl)
        let encoded = try JSONEncoder().encode(discovery)
        let rendered = String(data: encoded, encoding: .utf8)!

        XCTAssertTrue(discovery.isAvailable)
        XCTAssertEqual(discovery.sources.first, .translateKitKeychain)
        XCTAssertFalse(rendered.contains("do-not-render-this-secret"))
        XCTAssertFalse(rendered.contains("nor-this-one"))
    }

    func testAWSDiscoveryEnumeratesProfileNamesWithoutReadingValues() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-aws-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let awsDirectory = directory.appendingPathComponent(".aws", isDirectory: true)
        try FileManager.default.createDirectory(at: awsDirectory, withIntermediateDirectories: true)
        try """
        [default]
        region = eu-west-1
        [profile work]
        sso_start_url = https://example.awsapps.com/start
        """.write(to: awsDirectory.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try """
        [default]
        aws_access_key_id = must-not-appear
        [legacy]
        aws_secret_access_key = must-not-appear-either
        """.write(to: awsDirectory.appendingPathComponent("credentials"), atomically: true, encoding: .utf8)

        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: [:],
            processRunner: StubProcessRunner(),
            homeDirectory: directory
        )

        let discovery = try await resolver.discover(provider: .aws)
        let rendered = String(data: try JSONEncoder().encode(discovery), encoding: .utf8)!

        XCTAssertEqual(discovery.profiles, ["default", "legacy", "work"])
        XCTAssertFalse(rendered.contains("must-not-appear"))
    }

    func testAWSDiscoveryDoesNotClaimAnUnverifiedNativeCredential() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-empty-aws-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: [:],
            processRunner: StubProcessRunner(),
            homeDirectory: directory
        )

        let discovery = try await resolver.discover(provider: .aws)

        XCTAssertFalse(discovery.isAvailable)
        XCTAssertEqual(discovery.sources, [.none])
    }

    func testAWSStaticModeUsesKeychainCredential() async throws {
        let store = MemorySecretStore(values: [
            SecretReference.translateKitAccount("aws_access_key_id"): "access",
            SecretReference.translateKitAccount("aws_secret_access_key"): "secret",
            SecretReference.translateKitAccount("aws_session_token"): "session"
        ])
        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "static"
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: StubProcessRunner()
        )

        let credential = try await resolver.resolve(for: .aws, configuration: configuration)

        XCTAssertEqual(
            credential,
            .awsStatic(accessKeyID: "access", secretAccessKey: "secret", sessionToken: "session")
        )
    }

    func testAWSProfileModeKeepsNativeProfileAheadOfStoredStaticKeys() async throws {
        let store = MemorySecretStore(values: [
            SecretReference.translateKitAccount("aws_access_key_id"): "access",
            SecretReference.translateKitAccount("aws_secret_access_key"): "secret"
        ])
        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "profile"
        configuration.providers.aws.profile = "work"
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: StubProcessRunner()
        )

        let credential = try await resolver.resolve(for: .aws, configuration: configuration)

        XCTAssertEqual(credential, .awsProfile("work"))
    }
}

private final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretReference: String]
    private(set) var writes: [SecretReference] = []

    init(values: [SecretReference: String] = [:]) {
        self.values = values
    }

    func value(for reference: SecretReference) throws -> String? {
        values[reference]
    }

    func set(_ value: String, for reference: SecretReference) throws {
        values[reference] = value
        writes.append(reference)
    }

    func delete(_ reference: SecretReference) throws {
        values.removeValue(forKey: reference)
    }
}

private struct StubProcessRunner: ProcessRunning {
    var results: [String: String] = [:]

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> String {
        let key = ([executable] + arguments).joined(separator: " ")
        guard let result = results[key] else {
            throw ProcessRunnerError.executableNotFound(executable)
        }
        return result
    }
}
