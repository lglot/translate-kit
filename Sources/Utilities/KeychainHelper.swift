import Foundation
import TranslateKitCore

enum KeychainHelper {
    private static let store = KeychainSecretStore()

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        do {
            try store.set(value, for: .translateKitAccount(key))
            return true
        } catch {
            return false
        }
    }

    static func get(_ key: String) -> String? {
        try? store.value(for: .translateKitAccount(key))
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        do {
            try store.delete(.translateKitAccount(key))
            return true
        } catch {
            return false
        }
    }
}
