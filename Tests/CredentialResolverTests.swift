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

    func testGoogleCLITokenIncludesADCQuotaProject() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-google-adc-tests-\(UUID().uuidString)", isDirectory: true)
        let gcloudDirectory = directory.appendingPathComponent(".config/gcloud", isDirectory: true)
        try FileManager.default.createDirectory(at: gcloudDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"quota_project_id":"billing-project"}"#.utf8).write(
            to: gcloudDirectory.appendingPathComponent("application_default_credentials.json")
        )
        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: [:],
            processRunner: StubProcessRunner(results: [
                "gcloud auth application-default print-access-token": "short-lived-token\n"
            ]),
            homeDirectory: directory
        )

        let credential = try await resolver.resolve(for: .googleCloud)

        XCTAssertEqual(
            credential,
            .bearerToken("short-lived-token", quotaProject: "billing-project")
        )
    }

    func testGoogleExplicitGCloudModeIgnoresStoredAPIKey() async throws {
        let store = MemorySecretStore(values: [
            SecretReference.translateKit(.googleCloud): "saved-api-key"
        ])
        let runner = StubProcessRunner(results: [
            "gcloud auth application-default print-access-token": "short-lived-token\n"
        ])
        var configuration = TranslateKitConfiguration.default
        configuration.providers.googleCloud.auth = "gcloud"
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: runner
        )

        let credential = try await resolver.resolve(
            for: .googleCloud,
            configuration: configuration
        )

        XCTAssertEqual(credential, .bearerToken("short-lived-token"))
    }

    func testGoogleExplicitAPIKeyModeDoesNotFallBackToGCloud() async throws {
        let runner = StubProcessRunner(results: [
            "gcloud auth application-default print-access-token": "short-lived-token\n"
        ])
        var configuration = TranslateKitConfiguration.default
        configuration.providers.googleCloud.auth = "api-key"
        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: [:],
            processRunner: runner
        )

        let credential = try await resolver.resolve(
            for: .googleCloud,
            configuration: configuration
        )

        XCTAssertEqual(credential, .none)
    }

    func testNativeCredentialResolutionPreservesTaskCancellation() async {
        var configuration = TranslateKitConfiguration.default
        configuration.providers.googleCloud.auth = "gcloud"
        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: [:],
            processRunner: CancellingProcessRunner()
        )

        do {
            _ = try await resolver.resolve(
                for: .googleCloud,
                configuration: configuration
            )
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testAzureExplicitEntraModeIgnoresStoredAPIKey() async throws {
        let store = MemorySecretStore(values: [
            SecretReference.translateKit(.azure): "saved-api-key"
        ])
        let runner = StubProcessRunner(results: [
            "az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken --output tsv": "short-lived-token\n"
        ])
        var configuration = TranslateKitConfiguration.default
        configuration.providers.azure.auth = "entra"
        configuration.providers.azure.endpoint =
            "https://translator-resource.cognitiveservices.azure.com"
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: runner
        )

        let credential = try await resolver.resolve(
            for: .azure,
            configuration: configuration
        )

        XCTAssertEqual(credential, .bearerToken("short-lived-token"))
    }

    func testAzureExplicitAPIKeyModeDoesNotFallBackToEntra() async throws {
        let runner = StubProcessRunner(results: [
            "az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken --output tsv": "short-lived-token\n"
        ])
        var configuration = TranslateKitConfiguration.default
        configuration.providers.azure.auth = "api-key"
        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: [:],
            processRunner: runner
        )

        let credential = try await resolver.resolve(
            for: .azure,
            configuration: configuration
        )

        XCTAssertEqual(credential, .none)
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

    func testDiscoveryDetectsNativeCloudSessionsWithoutMintingTokens() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-native-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".config/gcloud", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".azure", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(
            to: directory.appendingPathComponent(".config/gcloud/application_default_credentials.json")
        )
        try Data("{}".utf8).write(
            to: directory.appendingPathComponent(".azure/azureProfile.json")
        )
        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: [:],
            processRunner: RejectingProcessRunner(),
            homeDirectory: directory
        )

        let google = try await resolver.discover(provider: .googleCloud)
        let azure = try await resolver.discover(provider: .azure)

        XCTAssertTrue(google.sources.contains(.googleCloudCLI))
        XCTAssertTrue(azure.sources.contains(.azureCLI))
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

    func testAWSDiscoveryHonorsStandardFileOverrides() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-aws-override-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        let credentials = directory.appendingPathComponent("credentials")
        try "[profile work]\nregion = eu-west-1\n"
            .write(to: config, atomically: true, encoding: .utf8)
        try "[legacy]\naws_access_key_id = hidden\n"
            .write(to: credentials, atomically: true, encoding: .utf8)
        let resolver = CredentialResolver(
            secretStore: MemorySecretStore(),
            environment: [
                "AWS_CONFIG_FILE": config.path,
                "AWS_SHARED_CREDENTIALS_FILE": credentials.path
            ],
            processRunner: StubProcessRunner(),
            homeDirectory: directory
        )

        let discovery = try await resolver.discover(provider: .aws)

        XCTAssertEqual(discovery.profiles, ["legacy", "work"])
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

    func testStoresAWSStaticCredentialsAsOneAtomicKeychainItem() async throws {
        let store = MemorySecretStore()
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: StubProcessRunner()
        )
        try resolver.storeAWSStatic(
            accessKeyID: "access",
            secretAccessKey: "secret",
            sessionToken: "session"
        )
        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "static"

        let credential = try await resolver.resolve(for: .aws, configuration: configuration)

        XCTAssertEqual(
            credential,
            .awsStatic(accessKeyID: "access", secretAccessKey: "secret", sessionToken: "session")
        )
        XCTAssertEqual(
            store.writes,
            [SecretReference.translateKitAccount("aws_static_credentials")]
        )
    }

    func testFailedAtomicAWSStaticWritePreservesPreviousCredential() async throws {
        let accessReference = SecretReference.translateKitAccount("aws_access_key_id")
        let secretReference = SecretReference.translateKitAccount("aws_secret_access_key")
        let tokenReference = SecretReference.translateKitAccount("aws_session_token")
        let bundleReference = SecretReference.translateKitAccount("aws_static_credentials")
        let store = FailingSecretStore(
            values: [
                accessReference: "old-access",
                secretReference: "old-secret",
                tokenReference: "old-token"
            ],
            failingReference: bundleReference
        )
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: StubProcessRunner()
        )

        XCTAssertThrowsError(try resolver.storeAWSStatic(
            accessKeyID: "new-access",
            secretAccessKey: "new-secret",
            sessionToken: "new-token"
        ))

        XCTAssertEqual(try store.value(for: accessReference), "old-access")
        XCTAssertEqual(try store.value(for: secretReference), "old-secret")
        XCTAssertEqual(try store.value(for: tokenReference), "old-token")

        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "static"
        let credential = try await resolver.resolve(for: .aws, configuration: configuration)
        XCTAssertEqual(
            credential,
            .awsStatic(
                accessKeyID: "old-access",
                secretAccessKey: "old-secret",
                sessionToken: "old-token"
            )
        )
    }

    func testAWSDeleteTombstonePreventsLegacyCredentialFromReappearing() async throws {
        let store = MemorySecretStore(values: [
            SecretReference.translateKitAccount("aws_access_key_id"): "legacy-access",
            SecretReference.translateKitAccount("aws_secret_access_key"): "legacy-secret"
        ])
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: StubProcessRunner()
        )
        try resolver.deleteAWSStatic()
        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "static"

        let credential = try await resolver.resolve(for: .aws, configuration: configuration)

        XCTAssertEqual(credential, .none)
        XCTAssertEqual(
            store.writes,
            [SecretReference.translateKitAccount("aws_static_credentials")]
        )
    }

    func testAWSDeleteReportsLegacyCleanupFailureButKeepsTombstoneActive() async throws {
        let secretReference = SecretReference.translateKitAccount("aws_secret_access_key")
        let store = FailingDeleteSecretStore(
            values: [
                SecretReference.translateKitAccount("aws_access_key_id"): "legacy-access",
                secretReference: "legacy-secret"
            ],
            failingReference: secretReference
        )
        let resolver = CredentialResolver(
            secretStore: store,
            environment: [:],
            processRunner: StubProcessRunner()
        )

        XCTAssertThrowsError(try resolver.deleteAWSStatic()) { error in
            XCTAssertEqual(
                error as? CredentialResolverError,
                .awsLegacyCredentialCleanupFailed
            )
        }

        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "static"
        let credential = try await resolver.resolve(for: .aws, configuration: configuration)
        XCTAssertEqual(
            credential,
            .none
        )
        XCTAssertEqual(try store.value(for: secretReference), "legacy-secret")
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

private struct RejectingProcessRunner: ProcessRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> String {
        XCTFail("Discovery must not execute \(executable)")
        throw ProcessRunnerError.launchFailed(executable)
    }
}

private struct CancellingProcessRunner: ProcessRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> String {
        throw CancellationError()
    }
}

private final class FailingSecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretReference: String]
    private let failingReference: SecretReference

    init(values: [SecretReference: String], failingReference: SecretReference) {
        self.values = values
        self.failingReference = failingReference
    }

    func value(for reference: SecretReference) throws -> String? {
        values[reference]
    }

    func set(_ value: String, for reference: SecretReference) throws {
        if reference == failingReference {
            throw SecretStoreError.invalidData
        }
        values[reference] = value
    }

    func delete(_ reference: SecretReference) throws {
        values.removeValue(forKey: reference)
    }
}

private final class FailingDeleteSecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretReference: String]
    private let failingReference: SecretReference

    init(values: [SecretReference: String], failingReference: SecretReference) {
        self.values = values
        self.failingReference = failingReference
    }

    func value(for reference: SecretReference) throws -> String? {
        values[reference]
    }

    func set(_ value: String, for reference: SecretReference) throws {
        values[reference] = value
    }

    func delete(_ reference: SecretReference) throws {
        if reference == failingReference {
            throw SecretStoreError.invalidData
        }
        values.removeValue(forKey: reference)
    }
}
