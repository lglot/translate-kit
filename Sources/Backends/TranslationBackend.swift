import Foundation

protocol TranslationBackend: Sendable {
    var id: String { get }
    var name: String { get }
    var requiresAPIKey: Bool { get }
    var isAvailable: Bool { get }

    func translate(
        _ text: String,
        from source: Language,
        to target: Language
    ) async throws -> TranslationResult
}
