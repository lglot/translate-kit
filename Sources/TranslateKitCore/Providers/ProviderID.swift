import Foundation

public enum ProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case apple
    case deepl
    case googleCloud = "google-cloud"
    case azure
    case aws
    case libretranslate
}
