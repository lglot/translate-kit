import Foundation

public enum ConfigurationEditor {
    public static let keys: [String] = [
        "version",
        "translation.provider",
        "translation.first_language",
        "translation.second_language",
        "providers.deepl.plan",
        "providers.google_cloud.auth",
        "providers.azure.auth",
        "providers.azure.endpoint",
        "providers.azure.region",
        "providers.aws.auth",
        "providers.aws.profile",
        "providers.aws.region",
        "providers.libretranslate.endpoint"
    ]

    public static func get(
        _ key: String,
        from configuration: TranslateKitConfiguration
    ) throws -> String {
        switch key {
        case "version": String(configuration.version)
        case "translation.provider": configuration.translation.provider
        case "translation.first_language": configuration.translation.firstLanguage
        case "translation.second_language": configuration.translation.secondLanguage
        case "providers.deepl.plan": configuration.providers.deepl.plan
        case "providers.google_cloud.auth": configuration.providers.googleCloud.auth
        case "providers.azure.auth": configuration.providers.azure.auth
        case "providers.azure.endpoint": configuration.providers.azure.endpoint
        case "providers.azure.region": configuration.providers.azure.region
        case "providers.aws.auth": configuration.providers.aws.auth
        case "providers.aws.profile": configuration.providers.aws.profile
        case "providers.aws.region": configuration.providers.aws.region
        case "providers.libretranslate.endpoint": configuration.providers.libretranslate.endpoint
        default: throw ConfigurationEditorError.unknownKey(key)
        }
    }

    public static func set(
        _ key: String,
        value: String,
        in configuration: inout TranslateKitConfiguration
    ) throws {
        var candidate = configuration
        switch key {
        case "version":
            guard let version = Int(value) else {
                throw ConfigurationEditorError.invalidValue(key, value)
            }
            candidate.version = version
        case "translation.provider": candidate.translation.provider = value
        case "translation.first_language": candidate.translation.firstLanguage = value
        case "translation.second_language": candidate.translation.secondLanguage = value
        case "providers.deepl.plan": candidate.providers.deepl.plan = value
        case "providers.google_cloud.auth": candidate.providers.googleCloud.auth = value
        case "providers.azure.auth": candidate.providers.azure.auth = value
        case "providers.azure.endpoint": candidate.providers.azure.endpoint = value
        case "providers.azure.region": candidate.providers.azure.region = value
        case "providers.aws.auth": candidate.providers.aws.auth = value
        case "providers.aws.profile": candidate.providers.aws.profile = value
        case "providers.aws.region": candidate.providers.aws.region = value
        case "providers.libretranslate.endpoint": candidate.providers.libretranslate.endpoint = value
        default: throw ConfigurationEditorError.unknownKey(key)
        }
        do {
            try candidate.validate()
            configuration = candidate
        } catch {
            throw ConfigurationEditorError.invalidValue(key, value)
        }
    }

    public static func unset(
        _ key: String,
        in configuration: inout TranslateKitConfiguration
    ) throws {
        let defaultValue = try get(key, from: .default)
        try set(key, value: defaultValue, in: &configuration)
    }
}

public enum ConfigurationEditorError: LocalizedError, Equatable, Sendable {
    case unknownKey(String)
    case invalidValue(String, String)

    public var errorDescription: String? {
        switch self {
        case .unknownKey(let key):
            return "Unknown configuration key: \(key)"
        case .invalidValue(let key, let value):
            return "Invalid value for \(key): \(value)"
        }
    }
}
