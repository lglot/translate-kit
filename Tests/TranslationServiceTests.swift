import Foundation
import XCTest
@testable import TranslateKitCore

final class TranslationServiceTests: XCTestCase {
    func testRegistryContainsEverySupportedProviderInStableOrder() {
        XCTAssertEqual(
            ProviderRegistry.descriptors.map(\.id),
            [.apple, .deepl, .googleCloud, .azure, .aws, .libretranslate]
        )
        XCTAssertEqual(ProviderRegistry.descriptors.first?.privacy, .onDevice)
        XCTAssertEqual(ProviderRegistry.descriptors.last?.privacy, .configuredServer)
    }

    func testDirectionUsesConfiguredPairWhenNoOverridesAreProvided() throws {
        let pair = LanguagePair(first: .italian, second: .english)

        let direction = try TranslationDirectionResolver.resolve(
            text: "Hello, this sentence is clearly written in English.",
            source: nil,
            target: nil,
            pair: pair
        )

        XCTAssertEqual(direction.source, .english)
        XCTAssertEqual(direction.target, .italian)
    }

    func testTargetOnlyUsesProviderAutoDetection() throws {
        let direction = try TranslationDirectionResolver.resolve(
            text: "Bonjour",
            source: nil,
            target: .italian,
            pair: LanguagePair(first: .italian, second: .english)
        )

        XCTAssertEqual(direction.source, .auto)
        XCTAssertEqual(direction.target, .italian)
    }

    func testSourceOnlyMustBelongToConfiguredPair() {
        XCTAssertThrowsError(try TranslationDirectionResolver.resolve(
            text: "Bonjour",
            source: .french,
            target: nil,
            pair: LanguagePair(first: .italian, second: .english)
        )) { error in
            XCTAssertEqual(error as? TranslationDirectionError, .sourceOutsideConfiguredPair("fr"))
        }
    }

    func testExplicitDirectionIsPreserved() throws {
        let direction = try TranslationDirectionResolver.resolve(
            text: "Olá",
            source: Language(rawValue: "pt-BR")!,
            target: .japanese,
            pair: LanguagePair(first: .italian, second: .english)
        )

        XCTAssertEqual(direction.source.rawValue, "pt-BR")
        XCTAssertEqual(direction.target, .japanese)
    }

    func testAutomaticDirectionRejectsPairWithSameBaseLanguage() {
        let pair = LanguagePair(
            first: Language(rawValue: "pt-BR")!,
            second: Language(rawValue: "pt-PT")!
        )

        XCTAssertThrowsError(try TranslationDirectionResolver.resolve(
            text: "Olá, este texto não identifica de forma confiável a variante regional.",
            source: nil,
            target: nil,
            pair: pair
        )) { error in
            XCTAssertEqual(
                error as? TranslationDirectionError,
                .ambiguousConfiguredPair("pt-BR", "pt-PT")
            )
        }
    }

    func testTranslationServiceDoesNotFallbackAfterSelectedProviderFails() async {
        let resolver = RecordingBackendResolver(error: .authenticationFailed("DeepL"))
        let service = TranslationService(backendResolver: resolver)
        var configuration = TranslateKitConfiguration.default
        configuration.translation.provider = "deepl"

        await XCTAssertThrowsErrorAsyncService {
            _ = try await service.translate(
                TranslationRequest(text: "Ciao", source: .italian, target: .english),
                configuration: configuration
            )
        } verify: { error in
            XCTAssertEqual(error as? TranslationError, .authenticationFailed("DeepL"))
        }
        let requests = await resolver.requestedProviders()
        XCTAssertEqual(requests, [.deepl])
    }

    func testRegistryCreatesLibreTranslateWithoutCredential() async throws {
        let registry = ProviderRegistry(
            credentialResolver: StubCredentialResolver(credentials: [.libretranslate: .none]),
            httpClient: NoRequestHTTPClient(),
            appleBackendFactory: { StubBackend(id: "apple") }
        )

        let backend = try await registry.backend(
            for: .libretranslate,
            configuration: .default
        )

        XCTAssertEqual(backend.id, "libretranslate")
        XCTAssertFalse(backend.requiresAPIKey)
    }
}

private actor RecordingBackendResolver: BackendResolving {
    let error: TranslationError
    private var providers: [ProviderID] = []

    init(error: TranslationError) {
        self.error = error
    }

    func backend(
        for provider: ProviderID,
        configuration: TranslateKitConfiguration
    ) async throws -> any TranslationBackend {
        providers.append(provider)
        return StubBackend(id: provider.rawValue, error: error)
    }

    func requestedProviders() -> [ProviderID] {
        providers
    }
}

private struct StubCredentialResolver: CredentialResolving {
    let credentials: [ProviderID: ProviderCredential]

    func resolve(
        for provider: ProviderID,
        configuration: TranslateKitConfiguration
    ) async throws -> ProviderCredential {
        credentials[provider] ?? .none
    }

    func discover(provider: ProviderID) async throws -> CredentialDiscovery {
        CredentialDiscovery(provider: provider, isAvailable: credentials[provider] != nil, sources: [.none])
    }
}

private struct NoRequestHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        XCTFail("No HTTP request expected")
        throw TranslationError.invalidResponse
    }
}

private struct StubBackend: TranslationBackend {
    let id: String
    let error: TranslationError?
    let name = "Stub"
    let requiresAPIKey = false
    let isAvailable = true

    init(id: String, error: TranslationError? = nil) {
        self.id = id
        self.error = error
    }

    func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        if let error { throw error }
        return TranslationResult(
            sourceText: text,
            translatedText: text,
            sourceLanguage: source,
            targetLanguage: target,
            backend: name
        )
    }
}

private func XCTAssertThrowsErrorAsyncService<T>(
    _ expression: () async throws -> T,
    verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        verify(error)
    }
}
