import Foundation

public enum ProviderPrivacy: String, Codable, Equatable, Sendable {
    case onDevice = "on-device"
    case cloudService = "cloud-service"
    case configuredServer = "configured-server"
}

public enum CredentialRequirement: String, Codable, Equatable, Sendable {
    case none
    case apiKey
    case apiKeyOrNative = "api-key-or-native"
    case nativeChainOrStatic = "native-chain-or-static"
    case optionalAPIKey = "optional-api-key"
}

public struct ProviderDescriptor: Codable, Equatable, Sendable {
    public let id: ProviderID
    public let name: String
    public let privacy: ProviderPrivacy
    public let credentialRequirement: CredentialRequirement

    public init(
        id: ProviderID,
        name: String,
        privacy: ProviderPrivacy,
        credentialRequirement: CredentialRequirement
    ) {
        self.id = id
        self.name = name
        self.privacy = privacy
        self.credentialRequirement = credentialRequirement
    }
}

public struct ProviderState: Codable, Equatable, Sendable {
    public let descriptor: ProviderDescriptor
    public let isConfigured: Bool
    public let credentialSources: [CredentialSource]
    public let profiles: [String]

    public init(
        descriptor: ProviderDescriptor,
        isConfigured: Bool,
        credentialSources: [CredentialSource],
        profiles: [String] = []
    ) {
        self.descriptor = descriptor
        self.isConfigured = isConfigured
        self.credentialSources = credentialSources
        self.profiles = profiles
    }
}

public protocol BackendResolving: Sendable {
    func backend(
        for provider: ProviderID,
        configuration: TranslateKitConfiguration
    ) async throws -> any TranslationBackend
}

public struct ProviderRegistry: BackendResolving, Sendable {
    public typealias AppleBackendFactory = @Sendable () -> any TranslationBackend

    public static let descriptors: [ProviderDescriptor] = [
        ProviderDescriptor(
            id: .apple,
            name: "Apple Translation",
            privacy: .onDevice,
            credentialRequirement: .none
        ),
        ProviderDescriptor(
            id: .deepl,
            name: "DeepL",
            privacy: .cloudService,
            credentialRequirement: .apiKey
        ),
        ProviderDescriptor(
            id: .googleCloud,
            name: "Google Cloud Translation",
            privacy: .cloudService,
            credentialRequirement: .apiKeyOrNative
        ),
        ProviderDescriptor(
            id: .azure,
            name: "Azure Translator",
            privacy: .cloudService,
            credentialRequirement: .apiKeyOrNative
        ),
        ProviderDescriptor(
            id: .aws,
            name: "Amazon Translate",
            privacy: .cloudService,
            credentialRequirement: .nativeChainOrStatic
        ),
        ProviderDescriptor(
            id: .libretranslate,
            name: "LibreTranslate",
            privacy: .configuredServer,
            credentialRequirement: .optionalAPIKey
        )
    ]

    private let credentialResolver: any CredentialResolving
    private let httpClient: any HTTPClient
    private let appleBackendFactory: AppleBackendFactory?

    public init(
        credentialResolver: any CredentialResolving = CredentialResolver(),
        httpClient: any HTTPClient = URLSessionHTTPClient.shared,
        appleBackendFactory: AppleBackendFactory? = nil
    ) {
        self.credentialResolver = credentialResolver
        self.httpClient = httpClient
        self.appleBackendFactory = appleBackendFactory
    }

    public func backend(
        for provider: ProviderID,
        configuration: TranslateKitConfiguration
    ) async throws -> any TranslationBackend {
        try configuration.validate()

        if provider == .apple {
            guard let appleBackendFactory else {
                throw TranslationError.backendUnavailable("Apple Translation")
            }
            return appleBackendFactory()
        }

        let credential = try await credentialResolver.resolve(
            for: provider,
            configuration: configuration
        )
        switch provider {
        case .apple:
            throw TranslationError.backendUnavailable("Apple Translation")
        case .deepl:
            guard credential.isAPIKey else { throw TranslationError.apiKeyMissing("DeepL") }
            return DeepLBackend(
                credential: credential,
                configuration: configuration.providers.deepl,
                httpClient: httpClient
            )
        case .googleCloud:
            guard credential.isAPIKey || credential.isBearerToken else {
                throw TranslationError.apiKeyMissing("Google Cloud")
            }
            return GoogleCloudBackend(credential: credential, httpClient: httpClient)
        case .azure:
            guard credential.isAPIKey || credential.isBearerToken else {
                throw TranslationError.apiKeyMissing("Azure Translator")
            }
            return AzureBackend(
                credential: credential,
                configuration: configuration.providers.azure,
                httpClient: httpClient
            )
        case .aws:
            do {
                let client = try await AWSSDKTranslateClient.make(
                    configuration: configuration.providers.aws,
                    credential: credential
                )
                return AWSBackend(client: client)
            } catch {
                throw TranslationError.invalidConfiguration("AWS profile or region")
            }
        case .libretranslate:
            return LibreTranslateBackend(
                credential: credential,
                configuration: configuration.providers.libretranslate,
                httpClient: httpClient
            )
        }
    }

    public func states(configuration: TranslateKitConfiguration) async -> [ProviderState] {
        await withTaskGroup(of: ProviderState.self) { group in
            for descriptor in Self.descriptors {
                group.addTask {
                    if descriptor.id == .apple || descriptor.id == .libretranslate {
                        return ProviderState(
                            descriptor: descriptor,
                            isConfigured: true,
                            credentialSources: [.none]
                        )
                    }
                    let discovery = try? await credentialResolver.discover(provider: descriptor.id)
                    return ProviderState(
                        descriptor: descriptor,
                        isConfigured: discovery?.isAvailable ?? false,
                        credentialSources: discovery?.sources ?? [.none],
                        profiles: discovery?.profiles ?? []
                    )
                }
            }
            var states: [ProviderState] = []
            for await state in group { states.append(state) }
            let order = Dictionary(uniqueKeysWithValues: Self.descriptors.enumerated().map { ($1.id, $0) })
            return states.sorted { order[$0.descriptor.id, default: 0] < order[$1.descriptor.id, default: 0] }
        }
    }
}
