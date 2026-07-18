import Foundation
import TranslateKitApple
import TranslateKitCore

@MainActor
final class BackendManager: ObservableObject {
    static let shared = BackendManager(
        preferences: PreferencesManager.shared,
        registry: ProviderRegistry(appleBackendFactory: { AppleBackend() })
    )

    @Published private(set) var providers: [ProviderState]
    @Published private(set) var activeBackendID: String

    private let preferences: PreferencesManager
    private let registry: ProviderRegistry

    var activeProvider: ProviderDescriptor {
        providers.first { $0.descriptor.id.rawValue == activeBackendID }?.descriptor
            ?? ProviderRegistry.descriptors[0]
    }

    init(preferences: PreferencesManager, registry: ProviderRegistry) {
        self.preferences = preferences
        self.registry = registry
        activeBackendID = preferences.activeBackendID
        providers = ProviderRegistry.descriptors.map { descriptor in
            ProviderState(
                descriptor: descriptor,
                isConfigured: descriptor.id == .apple || descriptor.id == .libretranslate,
                credentialSources: [.none]
            )
        }

        Task { [weak self] in
            await self?.reload()
        }
    }

    func reload() async {
        guard let configuration = try? preferences.validatedConfiguration() else { return }
        providers = await registry.states(configuration: configuration)
        activeBackendID = preferences.activeBackendID
    }

    func setActive(_ provider: ProviderID) {
        guard ProviderRegistry.descriptors.contains(where: { $0.id == provider }) else { return }
        preferences.activeBackendID = provider.rawValue
        activeBackendID = preferences.activeBackendID
    }
}
