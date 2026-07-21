import Foundation
import XCTest
@testable import TranslateKitCore

final class ProviderRegistryTests: XCTestCase {
    func testEveryRegisteredProviderReportsBackendAvailability() async {
        let registry = ProviderRegistry(
            credentialResolver: ProviderStateCredentialResolver(discoveries: [:])
        )

        let states = await registry.states(configuration: .default)

        XCTAssertEqual(states.count, ProviderRegistry.descriptors.count)
        XCTAssertTrue(states.allSatisfy(\.isAvailable))
    }

    func testProviderStateRespectsExplicitGoogleAuthenticationMode() async throws {
        let resolver = ProviderStateCredentialResolver(discoveries: [
            .googleCloud: CredentialDiscovery(
                provider: .googleCloud,
                isAvailable: true,
                sources: [.googleCloudCLI]
            )
        ])
        let registry = ProviderRegistry(credentialResolver: resolver)
        var configuration = TranslateKitConfiguration.default
        configuration.providers.googleCloud.auth = "api-key"

        let apiKeyStates = await registry.states(configuration: configuration)
        let apiKeyState = try XCTUnwrap(apiKeyStates.first { $0.descriptor.id == .googleCloud })

        XCTAssertFalse(apiKeyState.isConfigured)
        XCTAssertEqual(apiKeyState.credentialSources, [.none])

        configuration.providers.googleCloud.auth = "gcloud"
        let gcloudStates = await registry.states(configuration: configuration)
        let gcloudState = try XCTUnwrap(gcloudStates.first { $0.descriptor.id == .googleCloud })

        XCTAssertTrue(gcloudState.isConfigured)
        XCTAssertEqual(gcloudState.credentialSources, [.googleCloudCLI])
    }

    func testAzureAutoStateRequiresCustomEndpointForEntraSession() async throws {
        let resolver = ProviderStateCredentialResolver(discoveries: [
            .azure: CredentialDiscovery(
                provider: .azure,
                isAvailable: true,
                sources: [.azureCLI]
            )
        ])
        let registry = ProviderRegistry(credentialResolver: resolver)
        var configuration = TranslateKitConfiguration.default

        let globalStates = await registry.states(configuration: configuration)
        let globalState = try XCTUnwrap(globalStates.first { $0.descriptor.id == .azure })

        XCTAssertFalse(globalState.isConfigured)
        XCTAssertEqual(globalState.credentialSources, [.none])

        configuration.providers.azure.endpoint =
            "https://translator-resource.cognitiveservices.azure.com"
        let customStates = await registry.states(configuration: configuration)
        let customState = try XCTUnwrap(customStates.first { $0.descriptor.id == .azure })

        XCTAssertTrue(customState.isConfigured)
        XCTAssertEqual(customState.credentialSources, [.azureCLI])

        configuration.providers.azure.endpoint =
            "https://translator-resource.cognitiveservices.azure.us"
        let sovereignStates = await registry.states(configuration: configuration)
        let sovereignState = try XCTUnwrap(sovereignStates.first { $0.descriptor.id == .azure })

        XCTAssertFalse(sovereignState.isConfigured)
        XCTAssertEqual(sovereignState.credentialSources, [.none])
    }

    func testProviderStateDoesNotUseAWSProfileForStaticMode() async throws {
        let resolver = ProviderStateCredentialResolver(discoveries: [
            .aws: CredentialDiscovery(
                provider: .aws,
                isAvailable: true,
                sources: [.awsProfile],
                profiles: ["work"]
            )
        ])
        let registry = ProviderRegistry(credentialResolver: resolver)
        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "static"

        let states = await registry.states(configuration: configuration)
        let state = try XCTUnwrap(states.first { $0.descriptor.id == .aws })

        XCTAssertFalse(state.isConfigured)
        XCTAssertEqual(state.credentialSources, [.none])
        XCTAssertEqual(state.profiles, ["work"])
    }

    func testAWSNamedProfileStateRequiresMatchingDiscoveredProfile() async throws {
        let resolver = ProviderStateCredentialResolver(discoveries: [
            .aws: CredentialDiscovery(
                provider: .aws,
                isAvailable: true,
                sources: [.environment, .awsProfile],
                profiles: ["other"]
            )
        ])
        let registry = ProviderRegistry(credentialResolver: resolver)
        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "profile"
        configuration.providers.aws.profile = "work"

        let missingStates = await registry.states(configuration: configuration)
        let missingState = try XCTUnwrap(missingStates.first { $0.descriptor.id == .aws })

        XCTAssertFalse(missingState.isConfigured)
        XCTAssertEqual(missingState.credentialSources, [.none])

        configuration.providers.aws.profile = "other"
        let matchingStates = await registry.states(configuration: configuration)
        let matchingState = try XCTUnwrap(matchingStates.first { $0.descriptor.id == .aws })

        XCTAssertTrue(matchingState.isConfigured)
        XCTAssertEqual(matchingState.credentialSources, [.awsProfile])
    }

    func testAWSStaticModeWithoutStaticCredentialDoesNotUseDefaultChain() async {
        let registry = ProviderRegistry(
            credentialResolver: ProviderStateCredentialResolver(discoveries: [:])
        )
        var configuration = TranslateKitConfiguration.default
        configuration.providers.aws.auth = "static"

        await XCTAssertThrowsErrorAsync {
            _ = try await registry.backend(for: .aws, configuration: configuration)
        } verify: { error in
            XCTAssertEqual(
                error as? TranslationError,
                .apiKeyMissing("Amazon Translate credentials")
            )
        }
    }
}

private struct ProviderStateCredentialResolver: CredentialResolving {
    let discoveries: [ProviderID: CredentialDiscovery]

    func resolve(
        for provider: ProviderID,
        configuration: TranslateKitConfiguration
    ) async throws -> ProviderCredential {
        .none
    }

    func discover(provider: ProviderID) async throws -> CredentialDiscovery {
        discoveries[provider] ?? CredentialDiscovery(
            provider: provider,
            isAvailable: provider == .apple,
            sources: [.none]
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
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
