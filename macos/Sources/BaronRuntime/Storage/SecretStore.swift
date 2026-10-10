import BaronCore
import Foundation
import Security

/// `host.secrets` and `secret` preferences: Keychain items with service `org.odh.baron.plugin.<id>` and the key as
/// account, on this Mac only (not synchronisable), readable after first unlock. Design: 05-storage.md
public struct SecretStore: Sendable {
    public static let valueLimit = 16 * 1024
    /// Tests use their own prefix so they never touch real plugins' items.
    public let servicePrefix: String

    public init(servicePrefix: String = "org.odh.baron.plugin.") {
        self.servicePrefix = servicePrefix
    }

    func base(_ pluginID: String, _ key: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicePrefix + pluginID]
        if let key { query[kSecAttrAccount as String] = key }
        return query
    }

    public func get(_ key: String, pluginID: String) throws -> String? {
        var query = base(pluginID, key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.failure(status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func set(_ key: String, _ value: String, pluginID: String) throws {
        try KeyValueStore.checkKey(key)
        let data = Data(value.utf8)
        guard data.count <= Self.valueLimit else {
            throw KeyValueStore.quotaError("A secret can be at most 16 KB", limit: Self.valueLimit, used: data.count)
        }
        let update = SecItemUpdate(base(pluginID, key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Self.failure(update) }
        var item = base(pluginID, key)
        item[kSecValueData as String] = data
        item[kSecAttrSynchronizable as String] = false
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "Baron plugin \(pluginID): \(key)"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Self.failure(status) }
    }

    public func remove(_ key: String, pluginID: String) throws {
        let status = SecItemDelete(base(pluginID, key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.failure(status) }
    }

    /// Every secret of the plugin, for uninstalling and resetting.
    public func removeAll(pluginID: String) throws {
        var status: OSStatus
        repeat { status = SecItemDelete(base(pluginID) as CFDictionary) } while status == errSecSuccess
        guard status == errSecItemNotFound else { throw Self.failure(status) }
    }

    /// The keys the plugin has stored, for checks after uninstalling.
    public func keys(pluginID: String) -> [String] {
        var query = base(pluginID)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    static func failure(_ status: OSStatus) -> HostError {
        .internalError("The Keychain refused: \(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")")
    }
}
