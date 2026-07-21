import Foundation

public protocol CredentialResolving: Sendable {
    func resolve(
        for provider: ProviderID,
        configuration: TranslateKitConfiguration
    ) async throws -> ProviderCredential

    func discover(provider: ProviderID) async throws -> CredentialDiscovery
}

public enum ProviderCredential: Equatable, Sendable {
    case apiKey(String)
    case bearerToken(String, quotaProject: String? = nil)
    case awsProfile(String?)
    case awsStatic(accessKeyID: String, secretAccessKey: String, sessionToken: String?)
    case none
}

public enum CredentialSource: String, Codable, Equatable, Sendable {
    case translateKitKeychain = "translate-kit-keychain"
    case environment
    case externalKeychain = "external-keychain"
    case googleCloudCLI = "gcloud"
    case azureCLI = "azure-cli"
    case awsProfile = "aws-profile"
    case awsNativeChain = "aws-native-chain"
    case none
}

public struct CredentialDiscovery: Codable, Equatable, Sendable {
    public let provider: ProviderID
    public let isAvailable: Bool
    public let sources: [CredentialSource]
    public let profiles: [String]

    public init(
        provider: ProviderID,
        isAvailable: Bool,
        sources: [CredentialSource],
        profiles: [String] = []
    ) {
        self.provider = provider
        self.isAvailable = isAvailable
        self.sources = sources
        self.profiles = profiles
    }
}

public struct CredentialResolver: CredentialResolving, Sendable {
    private static let awsStaticCredential = SecretReference.translateKitAccount(
        "aws_static_credentials"
    )
    private static let legacyAWSMutationMarker = SecretReference.translateKitAccount(
        "aws_static_credentials_update_in_progress"
    )

    private let secretStore: any SecretStore
    private let environment: [String: String]
    private let processRunner: any ProcessRunning
    private let homeDirectory: URL

    public init(
        secretStore: any SecretStore = KeychainSecretStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processRunner: any ProcessRunning = ProcessRunner(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.secretStore = secretStore
        self.environment = environment
        self.processRunner = processRunner
        self.homeDirectory = homeDirectory
    }

    public func resolve(
        for provider: ProviderID,
        configuration: TranslateKitConfiguration = .default
    ) async throws -> ProviderCredential {
        switch provider {
        case .apple:
            return .none
        case .deepl:
            return try keyCredential(
                provider: provider,
                environmentNames: ["DEEPL_AUTH_KEY"],
                externalReference: SecretReference(service: "deepl", account: "DEEPL_AUTH_KEY")
            ) ?? .none
        case .googleCloud:
            let key = try keyCredential(
                provider: provider,
                environmentNames: ["GOOGLE_CLOUD_API_KEY", "GOOGLE_API_KEY"]
            )
            switch configuration.providers.googleCloud.auth {
            case "api-key":
                return key ?? .none
            case "gcloud":
                return try await googleCloudToken()
            default:
                if let key { return key }
                return try await googleCloudToken()
            }
        case .azure:
            let key = try keyCredential(
                provider: provider,
                environmentNames: ["AZURE_TRANSLATOR_KEY"]
            )
            switch configuration.providers.azure.auth {
            case "api-key":
                return key ?? .none
            case "entra":
                guard TranslateKitConfiguration.isAzurePublicCustomEndpoint(
                    configuration.providers.azure.endpoint
                ) else {
                    return .none
                }
                return try await azureCLIToken()
            default:
                if let key { return key }
                guard TranslateKitConfiguration.isAzurePublicCustomEndpoint(
                    configuration.providers.azure.endpoint
                ) else {
                    return .none
                }
                return try await azureCLIToken()
            }
        case .aws:
            return try resolveAWS(configuration.providers.aws)
        case .libretranslate:
            return try keyCredential(
                provider: provider,
                environmentNames: ["LIBRETRANSLATE_API_KEY"]
            ) ?? .none
        }
    }

    public func discover(provider: ProviderID) async throws -> CredentialDiscovery {
        var sources: [CredentialSource] = []
        var profiles: [String] = []

        switch provider {
        case .apple:
            sources = [.none]
        case .deepl:
            if try hasValue(.translateKit(provider)) { sources.append(.translateKitKeychain) }
            if firstEnvironmentValue(["DEEPL_AUTH_KEY"]) != nil { sources.append(.environment) }
            if try hasValue(SecretReference(service: "deepl", account: "DEEPL_AUTH_KEY")) {
                sources.append(.externalKeychain)
            }
        case .googleCloud:
            if try hasValue(.translateKit(provider)) { sources.append(.translateKitKeychain) }
            if firstEnvironmentValue(["GOOGLE_CLOUD_API_KEY", "GOOGLE_API_KEY"]) != nil {
                sources.append(.environment)
            }
            if googleCloudSessionConfigured() {
                sources.append(.googleCloudCLI)
            }
        case .azure:
            if try hasValue(.translateKit(provider)) { sources.append(.translateKitKeychain) }
            if firstEnvironmentValue(["AZURE_TRANSLATOR_KEY"]) != nil { sources.append(.environment) }
            if azureCLISessionConfigured() {
                sources.append(.azureCLI)
            }
        case .aws:
            if try staticAWSCredential() != nil { sources.append(.translateKitKeychain) }
            if environmentAWSCredential() != nil { sources.append(.environment) }
            profiles = try awsProfileNames()
            if let selectedProfile = firstEnvironmentValue(["AWS_PROFILE", "AWS_DEFAULT_PROFILE"]) {
                profiles.append(selectedProfile)
                profiles = Array(Set(profiles)).sorted()
            }
            if !profiles.isEmpty { sources.append(.awsProfile) }
            if firstEnvironmentValue([
                "AWS_WEB_IDENTITY_TOKEN_FILE",
                "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI",
                "AWS_CONTAINER_CREDENTIALS_FULL_URI"
            ]) != nil {
                sources.append(.awsNativeChain)
            }
        case .libretranslate:
            if try hasValue(.translateKit(provider)) { sources.append(.translateKitKeychain) }
            if firstEnvironmentValue(["LIBRETRANSLATE_API_KEY"]) != nil { sources.append(.environment) }
        }

        return CredentialDiscovery(
            provider: provider,
            isAvailable: provider == .apple || sources.contains { $0 != .none },
            sources: sources.isEmpty ? [.none] : sources,
            profiles: profiles
        )
    }

    public func store(_ value: String, for provider: ProviderID) throws {
        guard !value.isEmpty, ![ProviderID.apple, .aws].contains(provider) else {
            throw CredentialResolverError.unsupportedSecret(provider)
        }
        try secretStore.set(value, for: .translateKit(provider))
    }

    public func delete(for provider: ProviderID) throws {
        guard ![ProviderID.apple, .aws].contains(provider) else {
            throw CredentialResolverError.unsupportedSecret(provider)
        }
        try secretStore.delete(.translateKit(provider))
    }

    public func storeAWSStatic(
        accessKeyID: String,
        secretAccessKey: String,
        sessionToken: String? = nil
    ) throws {
        guard !accessKeyID.isEmpty, !secretAccessKey.isEmpty else {
            throw CredentialResolverError.invalidAWSStaticCredential
        }
        let record = AWSStaticCredentialRecord(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            sessionToken: nonEmpty(sessionToken)
        )
        try secretStore.set(try record.encoded(), for: Self.awsStaticCredential)
        try removeLegacyAWSStaticCredential()
    }

    public func deleteAWSStatic() throws {
        try secretStore.set(
            try AWSStaticCredentialRecord.deleted.encoded(),
            for: Self.awsStaticCredential
        )
        try removeLegacyAWSStaticCredential()
    }

    private func keyCredential(
        provider: ProviderID,
        environmentNames: [String],
        externalReference: SecretReference? = nil
    ) throws -> ProviderCredential? {
        if let value = try nonEmpty(secretStore.value(for: .translateKit(provider))) {
            return .apiKey(value)
        }
        if let value = firstEnvironmentValue(environmentNames) {
            return .apiKey(value)
        }
        if let externalReference,
           let value = try nonEmpty(secretStore.value(for: externalReference)) {
            return .apiKey(value)
        }
        return nil
    }

    private func resolveAWS(_ configuration: AWSConfiguration) throws -> ProviderCredential {
        if configuration.auth == "static" {
            return try staticAWSCredential() ?? .none
        }
        let profile = nonEmpty(configuration.profile)
        return .awsProfile(profile)
    }

    private func staticAWSCredential() throws -> ProviderCredential? {
        if let value = try secretStore.value(for: Self.awsStaticCredential) {
            return try AWSStaticCredentialRecord.decode(value).credential
        }
        guard try !hasValue(Self.legacyAWSMutationMarker) else { return nil }
        guard
            let accessKeyID = try nonEmpty(secretStore.value(for: .translateKitAccount("aws_access_key_id"))),
            let secretAccessKey = try nonEmpty(secretStore.value(for: .translateKitAccount("aws_secret_access_key")))
        else {
            return nil
        }
        let sessionToken = try nonEmpty(secretStore.value(for: .translateKitAccount("aws_session_token")))
        return .awsStatic(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken
        )
    }

    private func environmentAWSCredential() -> ProviderCredential? {
        guard
            let accessKeyID = firstEnvironmentValue(["AWS_ACCESS_KEY_ID"]),
            let secretAccessKey = firstEnvironmentValue(["AWS_SECRET_ACCESS_KEY"])
        else {
            return nil
        }
        return .awsStatic(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            sessionToken: firstEnvironmentValue(["AWS_SESSION_TOKEN"])
        )
    }

    private func removeLegacyAWSStaticCredential() throws {
        var cleanupFailed = false
        for account in [
            "aws_access_key_id",
            "aws_secret_access_key",
            "aws_session_token",
            "aws_static_credentials_update_in_progress"
        ] {
            do {
                try secretStore.delete(.translateKitAccount(account))
            } catch {
                cleanupFailed = true
            }
        }
        if cleanupFailed {
            throw CredentialResolverError.awsLegacyCredentialCleanupFailed
        }
    }

    private func commandOutput(_ executable: String, arguments: [String]) async throws -> String? {
        do {
            let output = try await processRunner.run(executable, arguments: arguments, timeout: 5)
            return nonEmpty(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func googleCloudToken() async throws -> ProviderCredential {
        guard let token = try await commandOutput(
            "gcloud",
            arguments: ["auth", "application-default", "print-access-token"]
        ) else {
            return .none
        }
        return .bearerToken(token, quotaProject: googleCloudQuotaProject())
    }

    private func azureCLIToken() async throws -> ProviderCredential {
        guard let token = try await commandOutput(
            "az",
            arguments: [
                "account", "get-access-token",
                "--resource", "https://cognitiveservices.azure.com",
                "--query", "accessToken",
                "--output", "tsv"
            ]
        ) else {
            return .none
        }
        return .bearerToken(token)
    }

    private func googleCloudSessionConfigured() -> Bool {
        googleCloudCredentialsURL() != nil
    }

    private func googleCloudQuotaProject() -> String? {
        guard
            let url = googleCloudCredentialsURL(),
            let data = try? Data(contentsOf: url),
            let metadata = try? JSONDecoder().decode(GoogleCredentialMetadata.self, from: data)
        else {
            return nil
        }
        return nonEmpty(metadata.quotaProjectID)
    }

    private func googleCloudCredentialsURL() -> URL? {
        if let credentialsPath = firstEnvironmentValue(["GOOGLE_APPLICATION_CREDENTIALS"]) {
            let url = URL(fileURLWithPath: expandedPath(credentialsPath))
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let configurationDirectory = firstEnvironmentValue(["CLOUDSDK_CONFIG"])
            .map { URL(fileURLWithPath: expandedPath($0), isDirectory: true) }
            ?? homeDirectory.appendingPathComponent(".config/gcloud", isDirectory: true)
        let url = configurationDirectory.appendingPathComponent("application_default_credentials.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func azureCLISessionConfigured() -> Bool {
        let configurationDirectory = firstEnvironmentValue(["AZURE_CONFIG_DIR"])
            .map { URL(fileURLWithPath: expandedPath($0), isDirectory: true) }
            ?? homeDirectory.appendingPathComponent(".azure", isDirectory: true)
        return FileManager.default.fileExists(
            atPath: configurationDirectory.appendingPathComponent("azureProfile.json").path
        )
    }

    private func expandedPath(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private func awsProfileNames() throws -> [String] {
        let awsDirectory = homeDirectory.appendingPathComponent(".aws", isDirectory: true)
        let configURL = firstEnvironmentValue(["AWS_CONFIG_FILE"])
            .map { URL(fileURLWithPath: $0) }
            ?? awsDirectory.appendingPathComponent("config")
        let credentialsURL = firstEnvironmentValue(["AWS_SHARED_CREDENTIALS_FILE"])
            .map { URL(fileURLWithPath: $0) }
            ?? awsDirectory.appendingPathComponent("credentials")
        var names = Set<String>()
        try collectProfiles(from: configURL, configFile: true, into: &names)
        try collectProfiles(from: credentialsURL, configFile: false, into: &names)
        return names.sorted()
    }

    private func collectProfiles(
        from url: URL,
        configFile: Bool,
        into names: inout Set<String>
    ) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let source = try String(contentsOf: url, encoding: .utf8)
        for rawLine in source.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), line.hasSuffix("]") else { continue }
            var name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if configFile, name.hasPrefix("profile ") {
                name = String(name.dropFirst("profile ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty, !name.contains(" ") else { continue }
            names.insert(name)
        }
    }

    private func firstEnvironmentValue(_ names: [String]) -> String? {
        for name in names {
            if let value = nonEmpty(environment[name]) { return value }
        }
        return nil
    }

    private func hasValue(_ reference: SecretReference) throws -> Bool {
        try nonEmpty(secretStore.value(for: reference)) != nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private struct GoogleCredentialMetadata: Decodable {
    let quotaProjectID: String?

    private enum CodingKeys: String, CodingKey {
        case quotaProjectID = "quota_project_id"
    }
}

private struct AWSStaticCredentialRecord: Codable {
    private static let currentVersion = 1

    let version: Int
    let deleted: Bool
    let accessKeyID: String?
    let secretAccessKey: String?
    let sessionToken: String?

    init(accessKeyID: String, secretAccessKey: String, sessionToken: String?) {
        version = Self.currentVersion
        deleted = false
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }

    private init(deleted: Bool) {
        version = Self.currentVersion
        self.deleted = deleted
        accessKeyID = nil
        secretAccessKey = nil
        sessionToken = nil
    }

    static let deleted = AWSStaticCredentialRecord(deleted: true)

    var credential: ProviderCredential? {
        guard
            version == Self.currentVersion,
            !deleted,
            let accessKeyID,
            !accessKeyID.isEmpty,
            let secretAccessKey,
            !secretAccessKey.isEmpty
        else {
            return nil
        }
        return .awsStatic(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return value
    }

    static func decode(_ value: String) throws -> AWSStaticCredentialRecord {
        guard let data = value.data(using: .utf8) else {
            throw CredentialResolverError.awsCredentialStateInconsistent
        }
        do {
            let record = try JSONDecoder().decode(AWSStaticCredentialRecord.self, from: data)
            guard record.version == currentVersion else {
                throw CredentialResolverError.awsCredentialStateInconsistent
            }
            return record
        } catch is CredentialResolverError {
            throw CredentialResolverError.awsCredentialStateInconsistent
        } catch {
            throw CredentialResolverError.awsCredentialStateInconsistent
        }
    }
}

public enum CredentialResolverError: LocalizedError, Equatable {
    case unsupportedSecret(ProviderID)
    case invalidAWSStaticCredential
    case awsCredentialStateInconsistent
    case awsLegacyCredentialCleanupFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedSecret(let provider):
            return "Provider does not accept a single API key: \(provider.rawValue)"
        case .invalidAWSStaticCredential:
            return "AWS access key ID and secret access key are required"
        case .awsCredentialStateInconsistent:
            return "AWS static credentials are unavailable after a failed Keychain update"
        case .awsLegacyCredentialCleanupFailed:
            return "AWS static credentials changed, but legacy Keychain items could not be removed"
        }
    }
}

extension ProviderCredential {
    var isAPIKey: Bool {
        if case .apiKey = self { return true }
        return false
    }

    var isBearerToken: Bool {
        if case .bearerToken = self { return true }
        return false
    }
}
