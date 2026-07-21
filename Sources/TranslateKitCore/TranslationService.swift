import Foundation

public struct TranslationDirection: Equatable, Sendable {
    public let source: Language
    public let target: Language

    public init(source: Language, target: Language) {
        self.source = source
        self.target = target
    }
}

public enum TranslationDirectionResolver {
    public static func resolve(
        text: String,
        source: Language?,
        target: Language?,
        pair: LanguagePair
    ) throws -> TranslationDirection {
        switch (source, target) {
        case (nil, nil):
            guard pair.first.baseLanguageCode != pair.second.baseLanguageCode else {
                throw TranslationDirectionError.ambiguousConfiguredPair(
                    pair.first.rawValue,
                    pair.second.rawValue
                )
            }
            let direction = pair.direction(for: text)
            return TranslationDirection(source: direction.source, target: direction.target)
        case (nil, let target?):
            guard target.isValidTarget else {
                throw TranslationDirectionError.invalidTarget(target.rawValue)
            }
            return TranslationDirection(source: .auto, target: target)
        case (let source?, nil):
            guard source != .auto else {
                throw TranslationDirectionError.targetRequiredForAutoSource
            }
            guard source == pair.first || source == pair.second else {
                throw TranslationDirectionError.sourceOutsideConfiguredPair(source.rawValue)
            }
            return TranslationDirection(source: source, target: pair.target(for: source))
        case (let source?, let target?):
            guard target.isValidTarget else {
                throw TranslationDirectionError.invalidTarget(target.rawValue)
            }
            guard source != target else {
                throw TranslationDirectionError.identicalLanguages(source.rawValue)
            }
            return TranslationDirection(source: source, target: target)
        }
    }
}

public enum TranslationDirectionError: LocalizedError, Equatable, Sendable {
    case sourceOutsideConfiguredPair(String)
    case targetRequiredForAutoSource
    case invalidTarget(String)
    case identicalLanguages(String)
    case ambiguousConfiguredPair(String, String)

    public var errorDescription: String? {
        switch self {
        case .sourceOutsideConfiguredPair(let source):
            return "Source language \(source) is outside the configured pair"
        case .targetRequiredForAutoSource:
            return "A target language is required when the source is auto"
        case .invalidTarget(let target):
            return "Invalid target language: \(target)"
        case .identicalLanguages(let language):
            return "Source and target language must differ: \(language)"
        case .ambiguousConfiguredPair(let first, let second):
            return "Automatic direction cannot distinguish \(first) from \(second); specify source and target languages"
        }
    }
}

public struct TranslationRequest: Sendable {
    public let text: String
    public let source: Language?
    public let target: Language?
    public let provider: ProviderID?

    public init(
        text: String,
        source: Language? = nil,
        target: Language? = nil,
        provider: ProviderID? = nil
    ) {
        self.text = text
        self.source = source
        self.target = target
        self.provider = provider
    }
}

public struct TranslationService: Sendable {
    private let backendResolver: any BackendResolving

    public init(backendResolver: any BackendResolving) {
        self.backendResolver = backendResolver
    }

    public func translate(
        _ request: TranslationRequest,
        configuration: TranslateKitConfiguration
    ) async throws -> TranslationResult {
        try configuration.validate()
        let pair = LanguagePair(
            first: Language(rawValue: configuration.translation.firstLanguage)!,
            second: Language(rawValue: configuration.translation.secondLanguage)!
        )
        let direction = try TranslationDirectionResolver.resolve(
            text: request.text,
            source: request.source,
            target: request.target,
            pair: pair
        )
        guard let configuredProvider = ProviderID(rawValue: configuration.translation.provider) else {
            throw ConfigurationError.invalidValue(
                "translation.provider",
                configuration.translation.provider
            )
        }
        let provider = request.provider ?? configuredProvider
        let backend = try await backendResolver.backend(for: provider, configuration: configuration)
        return try await backend.translate(
            request.text,
            from: direction.source,
            to: direction.target
        )
    }
}
