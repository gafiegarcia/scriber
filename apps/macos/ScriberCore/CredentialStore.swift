import Foundation

enum CredentialStorageDomain: Hashable, Sendable {
    case dataProtection
    case legacy
}

protocol CredentialStorageBackend: Sendable {
    func read(from domain: CredentialStorageDomain) throws -> String?
    func write(_ value: String, to domain: CredentialStorageDomain) throws
    func delete(from domain: CredentialStorageDomain) throws
}

enum CredentialStoreError: Error, Equatable, LocalizedError {
    case persistenceVerificationFailed

    var errorDescription: String? {
        switch self {
        case .persistenceVerificationFailed:
            "The API key could not be verified after saving it to Keychain."
        }
    }
}

struct VerifiedCredentialStore<Backend: CredentialStorageBackend>: Sendable {
    let backend: Backend

    func read() throws -> String? {
        if let value = try backend.read(from: .dataProtection) {
            return value
        }

        guard let legacyValue = try backend.read(from: .legacy) else {
            return nil
        }
        try persistAndVerify(legacyValue)
        try backend.delete(from: .legacy)
        try restoreIfNeeded(legacyValue)
        return legacyValue
    }

    func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete()
            return
        }

        let hasLegacyValue = try backend.read(from: .legacy) != nil
        try persistAndVerify(trimmed)
        if hasLegacyValue {
            try backend.delete(from: .legacy)
            try restoreIfNeeded(trimmed)
        }
    }

    func delete() throws {
        try backend.delete(from: .dataProtection)
        try backend.delete(from: .legacy)
    }

    private func persistAndVerify(_ value: String) throws {
        try backend.write(value, to: .dataProtection)
        guard try backend.read(from: .dataProtection) == value else {
            throw CredentialStoreError.persistenceVerificationFailed
        }
    }

    private func restoreIfNeeded(_ expectedValue: String) throws {
        guard try backend.read(from: .dataProtection) != expectedValue else { return }
        try persistAndVerify(expectedValue)
    }
}
