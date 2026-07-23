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
    static let service = "com.gafiegarcia.scriber.elevenlabs-api-key"
    static let account = "default"
    private static let label = "Scriber ElevenLabs API key"
    private let store: VerifiedCredentialStore<KeychainStorageBackend>

    init() {
        store = VerifiedCredentialStore(
            backend: KeychainStorageBackend(
                service: Self.service,
                account: Self.account,
                label: Self.label
            ),
            policy: .loginKeychain
        )
    }

    func readAPIKey() throws -> String? {
        try store.read()
    }

    func saveAPIKey(_ value: String) throws {
        try store.save(value)
    }

    func deleteAPIKey() throws {
        try store.delete()
    }
}

private struct KeychainStorageBackend: CredentialStorageBackend {
    let service: String
    let account: String
    let label: String

    func read(from domain: CredentialStorageDomain) throws -> String? {
        var query = baseQuery(for: domain)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    func write(_ value: String, to domain: CredentialStorageDomain) throws {
        guard let data = value.data(using: .utf8),
              !value.isEmpty else {
            throw KeychainError.invalidData
        }
        let match = baseQuery(for: domain)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: label,
            kSecAttrDescription as String: "Stored locally for Scribe v2 transcription",
        ]
        let update = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = match
            attributes.forEach { add[$0.key] = $0.value }
            if domain == .dataProtection {
                add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        } else if update != errSecSuccess {
            throw KeychainError.unexpectedStatus(update)
        }
    }

    func delete(from domain: CredentialStorageDomain) throws {
        let status = SecItemDelete(baseQuery(for: domain) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for domain: CredentialStorageDomain) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: domain == .dataProtection,
        ]
    }
}
