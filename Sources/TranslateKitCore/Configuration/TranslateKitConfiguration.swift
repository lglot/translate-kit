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
        try Self.validateSecureURL(
            providers.azure.endpoint,
            key: "providers.azure.endpoint",
            allowsLoopbackHTTP: false
        )
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
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), let host = url.host else {
            throw ConfigurationError.invalidValue(key, value)
        }
        if scheme == "https" { return }
        if allowsLoopbackHTTP,
           scheme == "http",
           ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) {
            return
        }
        throw ConfigurationError.invalidValue(key, value)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case translation
        case providers
    }

    public init(from decoder: Decoder) throws {
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

    private enum CodingKeys: String, CodingKey {
        case provider
        case firstLanguage = "first_language"
        case secondLanguage = "second_language"
    }

    public init(from decoder: Decoder) throws {
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

    private enum CodingKeys: String, CodingKey {
        case deepl
        case googleCloud = "google_cloud"
        case azure
        case aws
        case libretranslate
    }

    public init(from decoder: Decoder) throws {
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
}

public struct GoogleCloudConfiguration: Codable, Equatable, Sendable {
    public var auth: String
    public init(auth: String = "auto") { self.auth = auth }
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
}

public struct LibreTranslateConfiguration: Codable, Equatable, Sendable {
    public var endpoint: String
    public init(endpoint: String = "http://localhost:5000") { self.endpoint = endpoint }
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
        case .invalidValue(let key, let value):
            return "Invalid value for \(key): \(value)"
        }
    }
}
