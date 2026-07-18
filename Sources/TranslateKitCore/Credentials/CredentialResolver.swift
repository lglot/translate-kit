import Foundation

public enum ProviderCredential: Equatable, Sendable {
    case apiKey(String)
    case bearerToken(String)
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

public struct CredentialResolver: Sendable {
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
            if let credential = try keyCredential(
                provider: provider,
                environmentNames: ["GOOGLE_CLOUD_API_KEY", "GOOGLE_API_KEY"]
            ) {
                return credential
            }
            if configuration.providers.googleCloud.auth != "api-key",
               let token = await commandOutput(
                   "gcloud",
                   arguments: ["auth", "application-default", "print-access-token"]
               ) {
                return .bearerToken(token)
            }
            return .none
        case .azure:
            if let credential = try keyCredential(
                provider: provider,
                environmentNames: ["AZURE_TRANSLATOR_KEY"]
            ) {
                return credential
            }
            if configuration.providers.azure.auth != "api-key",
               let token = await commandOutput(
                   "az",
                   arguments: [
                       "account", "get-access-token",
                       "--resource", "https://cognitiveservices.azure.com",
                       "--query", "accessToken",
                       "--output", "tsv"
                   ]
               ) {
                return .bearerToken(token)
            }
            return .none
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
            if await commandOutput(
                "gcloud",
                arguments: ["auth", "application-default", "print-access-token"]
            ) != nil {
                sources.append(.googleCloudCLI)
            }
        case .azure:
            if try hasValue(.translateKit(provider)) { sources.append(.translateKitKeychain) }
            if firstEnvironmentValue(["AZURE_TRANSLATOR_KEY"]) != nil { sources.append(.environment) }
            if await commandOutput(
                "az",
                arguments: [
                    "account", "get-access-token",
                    "--resource", "https://cognitiveservices.azure.com",
                    "--query", "accessToken",
                    "--output", "tsv"
                ]
            ) != nil {
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

    private func commandOutput(_ executable: String, arguments: [String]) async -> String? {
        guard let output = try? await processRunner.run(executable, arguments: arguments, timeout: 5) else {
            return nil
        }
        return nonEmpty(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func awsProfileNames() throws -> [String] {
        let awsDirectory = homeDirectory.appendingPathComponent(".aws", isDirectory: true)
        var names = Set<String>()
        try collectProfiles(from: awsDirectory.appendingPathComponent("config"), configFile: true, into: &names)
        try collectProfiles(from: awsDirectory.appendingPathComponent("credentials"), configFile: false, into: &names)
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

public enum CredentialResolverError: LocalizedError, Equatable {
    case unsupportedSecret(ProviderID)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSecret(let provider):
            return "Provider does not accept a single API key: \(provider.rawValue)"
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
