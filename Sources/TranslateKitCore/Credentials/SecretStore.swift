import Foundation
import Security

public struct SecretReference: Hashable, Sendable {
    public static let translateKitService = "com.translatekit.app"

    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public static func translateKit(_ provider: ProviderID) -> SecretReference {
        switch provider {
        case .apple:
            return translateKitAccount("apple")
        case .deepl:
            return translateKitAccount("deepl_api_key")
        case .googleCloud:
            return translateKitAccount("google_cloud_api_key")
        case .azure:
            return translateKitAccount("azure_translator_api_key")
        case .aws:
            return translateKitAccount("aws_access_key_id")
        case .libretranslate:
            return translateKitAccount("libretranslate_api_key")
        }
    }

    public static func translateKitAccount(_ account: String) -> SecretReference {
        SecretReference(service: translateKitService, account: account)
    }
}

public protocol SecretStore: Sendable {
    func value(for reference: SecretReference) throws -> String?
    func set(_ value: String, for reference: SecretReference) throws
    func delete(_ reference: SecretReference) throws
}

public struct KeychainSecretStore: SecretStore, Sendable {
    public init() {}

    public func value(for reference: SecretReference) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecretStoreError.keychain(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return value
    }

    public func set(_ value: String, for reference: SecretReference) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecretStoreError.invalidData
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.keychain(updateStatus)
        }

        var item = query
        item.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.keychain(addStatus)
        }
    }

    public func delete(_ reference: SecretReference) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }
}

public enum SecretStoreError: LocalizedError, Equatable {
    case keychain(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain operation failed with status \(status)"
        case .invalidData:
            return "Keychain item is not valid UTF-8 data"
        }
    }
}
