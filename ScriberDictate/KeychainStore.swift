import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData
    case accessCreationFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        case .invalidData:
            return "The stored API key could not be read."
        case .accessCreationFailed:
            return "Scriber Dictate could not restrict the API key to this app."
        }
    }
}

struct KeychainStore: Sendable {
    static let service = "com.gafiegarcia.scriber-dictate.elevenlabs-api-key"
    static let account = "default"
    private static let label = "Scriber Dictate ElevenLabs API key"

    func readAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        try restrictAPIKeyAccess()
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
        ]
        var attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: Self.label,
            kSecAttrDescription as String: "Stored locally for Scribe v2 transcription",
        ]
        attributes[kSecAttrAccess as String] = try applicationOnlyAccess()
        let update = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = match
            attributes.forEach { add[$0.key] = $0.value }
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        } else if update != errSecSuccess {
            throw KeychainError.unexpectedStatus(update)
        }
    }

    func deleteAPIKey() throws {
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

    private func restrictAPIKeyAccess() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let attributes: [String: Any] = [
            kSecAttrAccess as String: try applicationOnlyAccess(),
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private func applicationOnlyAccess() throws -> SecAccess {
        var access: SecAccess?
        // App Sandbox is intentionally disabled, so explicitly install a legacy
        // Keychain ACL whose nil trusted-app list means the calling app only.
        let status = SecAccessCreate(Self.label as CFString, nil, &access)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let access else { throw KeychainError.accessCreationFailed }
        return access
    }
}
