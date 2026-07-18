import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        case .invalidData:
            return "The stored API key could not be read."
        }
    }
}

struct KeychainStore: Sendable {
    static let service = "com.gafiegarcia.scriber-dictate.elevenlabs-api-key"
    static let account = "default"
    private static let label = "Scriber Dictate ElevenLabs API key"

    func readAPIKey() throws -> String? {
        if let value = try readAPIKey(usingDataProtectionKeychain: true) {
            return value
        }

        guard let legacyValue = try readAPIKey(usingDataProtectionKeychain: false) else {
            return nil
        }
        try saveAPIKey(legacyValue)
        return legacyValue
    }

    private func readAPIKey(usingDataProtectionKeychain: Bool) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if usingDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            try deleteAPIKey()
            return
        }
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: Self.label,
            kSecAttrDescription as String: "Stored locally for Scribe v2 transcription",
        ]
        let update = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = match
            attributes.forEach { add[$0.key] = $0.value }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        } else if update != errSecSuccess {
            throw KeychainError.unexpectedStatus(update)
        }
        try deleteLegacyAPIKey()
    }

    func deleteAPIKey() throws {
        let dataProtectionQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let dataProtectionStatus = SecItemDelete(dataProtectionQuery as CFDictionary)
        guard dataProtectionStatus == errSecSuccess || dataProtectionStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(dataProtectionStatus)
        }
        try deleteLegacyAPIKey()
    }

    private func deleteLegacyAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
