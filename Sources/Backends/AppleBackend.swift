import Foundation

struct AppleBackend: TranslationBackend {
    let id = "apple"
    let name = "Apple (On-Device)"
    let requiresAPIKey = false
    var isAvailable: Bool { true }

    func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult {
        throw TranslationError.backendUnavailable("Apple Translation uses SwiftUI integration")
    }
}
