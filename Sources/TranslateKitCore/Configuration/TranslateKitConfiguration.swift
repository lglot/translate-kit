import Foundation

public struct TranslateKitConfiguration: Codable, Equatable, Sendable {
    public var version: Int
    public var translation: TranslationConfiguration
    public var providers: ProviderConfigurations

    public init(
        version: Int = 1,
        translation: TranslationConfiguration = .init(),
        providers: ProviderConfigurations = .init()
    ) {
        self.version = version
        self.translation = translation
        self.providers = providers
    }

    public static let `default` = TranslateKitConfiguration()

    public func validate() throws {
        guard version == 1 else {
            throw ConfigurationError.unsupportedVersion(version)
        }
        guard Self.providerIDs.contains(translation.provider) else {
            throw ConfigurationError.invalidValue("translation.provider", translation.provider)
        }
        guard let first = Language(rawValue: translation.firstLanguage), first.isValidTarget else {
            throw ConfigurationError.invalidValue("translation.first_language", translation.firstLanguage)
        }
        guard let second = Language(rawValue: translation.secondLanguage), second.isValidTarget else {
            throw ConfigurationError.invalidValue("translation.second_language", translation.secondLanguage)
        }
        guard first != second else {
            throw ConfigurationError.invalidValue(
                "translation.second_language",
                "must differ from translation.first_language"
            )
        }
        guard ["free", "pro"].contains(providers.deepl.plan) else {
            throw ConfigurationError.invalidValue("providers.deepl.plan", providers.deepl.plan)
        }
        guard ["auto", "api-key", "gcloud"].contains(providers.googleCloud.auth) else {
            throw ConfigurationError.invalidValue("providers.google_cloud.auth", providers.googleCloud.auth)
        }
        guard ["auto", "api-key", "entra"].contains(providers.azure.auth) else {
            throw ConfigurationError.invalidValue("providers.azure.auth", providers.azure.auth)
        }
        try Self.validateAzureEndpoint(providers.azure.endpoint)
        if providers.azure.auth == "entra",
           !Self.isAzurePublicCustomEndpoint(providers.azure.endpoint) {
            throw ConfigurationError.invalidValue(
                "providers.azure.auth",
                "entra requires a public Azure custom-domain endpoint"
            )
        }
        guard ["auto", "profile", "static"].contains(providers.aws.auth) else {
            throw ConfigurationError.invalidValue("providers.aws.auth", providers.aws.auth)
        }
        try Self.validateSecureURL(
            providers.libretranslate.endpoint,
            key: "providers.libretranslate.endpoint",
            allowsLoopbackHTTP: true
        )
    }

    public static let providerIDs: Set<String> = [
        "apple", "deepl", "google-cloud", "azure", "aws", "libretranslate"
    ]

    private static func validateSecureURL(
        _ value: String,
        key: String,
        allowsLoopbackHTTP: Bool
    ) throws {
        guard
            let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(),
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw ConfigurationError.invalidValue(key, value)
        }
        if scheme == "https" { return }
        if allowsLoopbackHTTP,
           scheme == "http",
           ["localhost", "127.0.0.1", "::1"].contains(host) {
            return
        }
        throw ConfigurationError.invalidValue(key, value)
    }

    private static func validateAzureEndpoint(_ value: String) throws {
        let key = "providers.azure.endpoint"
        guard
            let components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            let host = components.host?.lowercased(),
            components.user == nil,
            components.password == nil,
            components.port == nil || components.port == 443,
            components.query == nil,
            components.fragment == nil
        else {
            throw ConfigurationError.invalidValue(key, value)
        }

        let fixedHosts: Set<String> = [
            "api.cognitive.microsofttranslator.com",
            "api-nam.cognitive.microsofttranslator.com",
            "api-apc.cognitive.microsofttranslator.com",
            "api-eur.cognitive.microsofttranslator.com",
            "api.cognitive.microsofttranslator.us",
            "api.translator.azure.cn"
        ]
        let isCustomDomain = isAzureCustomEndpoint(value)
        guard fixedHosts.contains(host) || isCustomDomain else {
            throw ConfigurationError.invalidValue(key, value)
        }
    }

    static func isAzureCustomEndpoint(_ value: String) -> Bool {
        guard let host = URLComponents(string: value)?.host?.lowercased() else {
            return false
        }
        let customDomainSuffixes = [
            ".cognitiveservices.azure.com",
            ".cognitiveservices.azure.us",
            ".cognitiveservices.azure.cn"
        ]
        return customDomainSuffixes.contains { suffix in
            host.hasSuffix(suffix) && host.count > suffix.count
        }
    }

    static func isAzurePublicCustomEndpoint(_ value: String) -> Bool {
        guard let host = URLComponents(string: value)?.host?.lowercased() else {
            return false
        }
        let suffix = ".cognitiveservices.azure.com"
        return host.hasSuffix(suffix) && host.count > suffix.count
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case translation
        case providers
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        translation = try container.decodeIfPresent(TranslationConfiguration.self, forKey: .translation) ?? .init()
        providers = try container.decodeIfPresent(ProviderConfigurations.self, forKey: .providers) ?? .init()
    }
}

public struct TranslationConfiguration: Codable, Equatable, Sendable {
    public var provider: String
    public var firstLanguage: String
    public var secondLanguage: String

    public init(provider: String = "apple", firstLanguage: String = "it", secondLanguage: String = "en") {
        self.provider = provider
        self.firstLanguage = firstLanguage
        self.secondLanguage = secondLanguage
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case provider
        case firstLanguage = "first_language"
        case secondLanguage = "second_language"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "apple"
        firstLanguage = try container.decodeIfPresent(String.self, forKey: .firstLanguage) ?? "it"
        secondLanguage = try container.decodeIfPresent(String.self, forKey: .secondLanguage) ?? "en"
    }
}

public struct ProviderConfigurations: Codable, Equatable, Sendable {
    public var deepl: DeepLConfiguration
    public var googleCloud: GoogleCloudConfiguration
    public var azure: AzureConfiguration
    public var aws: AWSConfiguration
    public var libretranslate: LibreTranslateConfiguration

    public init(
        deepl: DeepLConfiguration = .init(),
        googleCloud: GoogleCloudConfiguration = .init(),
        azure: AzureConfiguration = .init(),
        aws: AWSConfiguration = .init(),
        libretranslate: LibreTranslateConfiguration = .init()
    ) {
        self.deepl = deepl
        self.googleCloud = googleCloud
        self.azure = azure
        self.aws = aws
        self.libretranslate = libretranslate
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case deepl
        case googleCloud = "google_cloud"
        case azure
        case aws
        case libretranslate
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deepl = try container.decodeIfPresent(DeepLConfiguration.self, forKey: .deepl) ?? .init()
        googleCloud = try container.decodeIfPresent(GoogleCloudConfiguration.self, forKey: .googleCloud) ?? .init()
        azure = try container.decodeIfPresent(AzureConfiguration.self, forKey: .azure) ?? .init()
        aws = try container.decodeIfPresent(AWSConfiguration.self, forKey: .aws) ?? .init()
        libretranslate = try container.decodeIfPresent(LibreTranslateConfiguration.self, forKey: .libretranslate) ?? .init()
    }
}

public struct DeepLConfiguration: Codable, Equatable, Sendable {
    public var plan: String
    public init(plan: String = "free") { self.plan = plan }

    private enum CodingKeys: String, CodingKey, CaseIterable { case plan }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decodeIfPresent(String.self, forKey: .plan) ?? "free"
    }
}

public struct GoogleCloudConfiguration: Codable, Equatable, Sendable {
    public var auth: String
    public init(auth: String = "auto") { self.auth = auth }

    private enum CodingKeys: String, CodingKey, CaseIterable { case auth }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        auth = try container.decodeIfPresent(String.self, forKey: .auth) ?? "auto"
    }
}

public struct AzureConfiguration: Codable, Equatable, Sendable {
    public var auth: String
    public var endpoint: String
    public var region: String

    public init(
        auth: String = "auto",
        endpoint: String = "https://api.cognitive.microsofttranslator.com",
        region: String = ""
    ) {
        self.auth = auth
        self.endpoint = endpoint
        self.region = region
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case auth
        case endpoint
        case region
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        auth = try container.decodeIfPresent(String.self, forKey: .auth) ?? "auto"
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
            ?? "https://api.cognitive.microsofttranslator.com"
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
    }
}

public struct AWSConfiguration: Codable, Equatable, Sendable {
    public var auth: String
    public var profile: String
    public var region: String

    public init(auth: String = "profile", profile: String = "", region: String = "") {
        self.auth = auth
        self.profile = profile
        self.region = region
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case auth
        case profile
        case region
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        auth = try container.decodeIfPresent(String.self, forKey: .auth) ?? "profile"
        profile = try container.decodeIfPresent(String.self, forKey: .profile) ?? ""
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
    }
}

public struct LibreTranslateConfiguration: Codable, Equatable, Sendable {
    public var endpoint: String
    public init(endpoint: String = "http://localhost:5000") { self.endpoint = endpoint }

    private enum CodingKeys: String, CodingKey, CaseIterable { case endpoint }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
            ?? "http://localhost:5000"
    }
}

public struct LegacyTranslationPreferences: Sendable {
    public let provider: String
    public let firstLanguage: String
    public let secondLanguage: String
    public let deeplPlan: String

    public init(provider: String, firstLanguage: String, secondLanguage: String, deeplPlan: String) {
        self.provider = provider
        self.firstLanguage = firstLanguage
        self.secondLanguage = secondLanguage
        self.deeplPlan = deeplPlan
    }
}

public enum ConfigurationError: LocalizedError, Equatable {
    case missingFile(String)
    case malformed(String)
    case unknownKey(String)
    case unsupportedVersion(Int)
    case invalidValue(String, String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let path):
            return "Configuration file does not exist: \(path)"
        case .malformed(let message):
            return "Invalid TOML configuration: \(message)"
        case .unknownKey(let key):
            return "Unknown configuration key: \(key)"
        case .unsupportedVersion(let version):
            return "Unsupported configuration version: \(version)"
        case .invalidValue(let key, _):
            return "Invalid value for \(key)"
        }
    }
}

private struct AnyConfigurationCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func rejectUnknownKeys<Key>(
    in decoder: Decoder,
    allowed: Key.Type
) throws where Key: CodingKey & CaseIterable, Key.AllCases: Collection {
    let container = try decoder.container(keyedBy: AnyConfigurationCodingKey.self)
    let allowedKeys = Set(Key.allCases.map(\.stringValue))
    if let unknown = container.allKeys.first(where: { !allowedKeys.contains($0.stringValue) }) {
        let path = (decoder.codingPath.map(\.stringValue) + [unknown.stringValue])
            .joined(separator: ".")
        throw ConfigurationError.unknownKey(path)
    }
}
