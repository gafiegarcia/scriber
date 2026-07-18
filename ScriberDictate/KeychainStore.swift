import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData
    case persistenceVerificationFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        case .invalidData:
            return "The stored API key could not be read."
        case .persistenceVerificationFailed:
            return "The API key could not be verified after saving it to Keychain."
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
        try writeDataProtectionAPIKey(legacyValue)
        try verifyDataProtectionAPIKey(legacyValue)
        try deleteLegacyAPIKey()
        try restoreDataProtectionAPIKeyIfNeeded(legacyValue)
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
        query[kSecUseDataProtectionKeychain as String] = usingDataProtectionKeychain
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
        guard !trimmed.isEmpty else {
            try deleteAPIKey()
            return
        }
        let hasLegacyItem = try readAPIKey(usingDataProtectionKeychain: false) != nil
        try writeDataProtectionAPIKey(trimmed)
        try verifyDataProtectionAPIKey(trimmed)
        if hasLegacyItem {
            try deleteLegacyAPIKey()
            try restoreDataProtectionAPIKeyIfNeeded(trimmed)
        }
    }

    private func writeDataProtectionAPIKey(_ value: String) throws {
        guard let data = value.data(using: .utf8), !value.isEmpty else {
            throw KeychainError.invalidData
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
    }

    private func verifyDataProtectionAPIKey(_ expectedValue: String) throws {
        guard try readAPIKey(usingDataProtectionKeychain: true) == expectedValue else {
            throw KeychainError.persistenceVerificationFailed
        }
    }

    private func restoreDataProtectionAPIKeyIfNeeded(_ expectedValue: String) throws {
        guard try readAPIKey(usingDataProtectionKeychain: true) != expectedValue else { return }
        try writeDataProtectionAPIKey(expectedValue)
        try verifyDataProtectionAPIKey(expectedValue)
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
            kSecUseDataProtectionKeychain as String: false,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
