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
        let parentDirectory = url.deletingLastPathComponent()
        let parentDirectoryExists = fileManager.fileExists(atPath: parentDirectory.path)
        try fileManager.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !parentDirectoryExists {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: parentDirectory.path
            )
        }

        let encoder = TOMLEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
