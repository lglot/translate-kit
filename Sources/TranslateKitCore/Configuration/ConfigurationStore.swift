import Foundation
import TOML

public final class ConfigurationStore: @unchecked Sendable {
    public let url: URL

    private let fileManager: FileManager

    public init(url: URL = ConfigurationStore.defaultURL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("translate-kit", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    public func load() throws -> TranslateKitConfiguration {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ConfigurationError.missingFile(url.path)
        }
        do {
            return try decode(String(contentsOf: url, encoding: .utf8))
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.malformed(error.localizedDescription)
        }
    }

    public func loadOrCreate(
        legacy: LegacyTranslationPreferences? = nil
    ) throws -> TranslateKitConfiguration {
        if fileManager.fileExists(atPath: url.path) {
            return try load()
        }

        var configuration = TranslateKitConfiguration.default
        if let legacy {
            if TranslateKitConfiguration.providerIDs.contains(legacy.provider) {
                configuration.translation.provider = legacy.provider
            }
            if let language = Language(rawValue: legacy.firstLanguage), language.isValidTarget {
                configuration.translation.firstLanguage = language.rawValue
            }
            if let language = Language(rawValue: legacy.secondLanguage), language.isValidTarget {
                configuration.translation.secondLanguage = language.rawValue
            }
            if ["free", "pro"].contains(legacy.deeplPlan) {
                configuration.providers.deepl.plan = legacy.deeplPlan
            }
            if configuration.translation.firstLanguage == configuration.translation.secondLanguage {
                configuration.translation = .init()
            }
        }
        try save(configuration)
        return configuration
    }

    public func decode(_ source: String) throws -> TranslateKitConfiguration {
        try validateKnownKeys(in: source)
        do {
            let decoder = TOMLDecoder()
            let configuration = try decoder.decode(TranslateKitConfiguration.self, from: source)
            try configuration.validate()
            return configuration
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.malformed(error.localizedDescription)
        }
    }

    public func save(_ configuration: TranslateKitConfiguration) throws {
        try configuration.validate()
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = TOMLEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func validateKnownKeys(in source: String) throws {
        let allowedSections: Set<String> = [
            "translation",
            "providers",
            "providers.deepl",
            "providers.google_cloud",
            "providers.azure",
            "providers.aws",
            "providers.libretranslate"
        ]
        let allowedKeys: Set<String> = [
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

        var section = ""
        for rawLine in source.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard allowedSections.contains(section) else {
                    throw ConfigurationError.unknownKey(section)
                }
                continue
            }

            guard let separator = line.firstIndex(of: "=") else {
                throw ConfigurationError.malformed("Expected key = value")
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let path = section.isEmpty ? key : "\(section).\(key)"
            guard allowedKeys.contains(path) else {
                throw ConfigurationError.unknownKey(path)
            }
        }
    }
}
