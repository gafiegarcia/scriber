import Foundation

enum CredentialStorageDomain: Hashable, Sendable {
    case dataProtection
    case legacy
}

enum CredentialStoragePolicy: Hashable, Sendable {
    case loginKeychain
    case dataProtectionKeychain

    var primaryDomain: CredentialStorageDomain {
        switch self {
        case .loginKeychain: .legacy
        case .dataProtectionKeychain: .dataProtection
        }
    }
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
    let policy: CredentialStoragePolicy

    func read() throws -> String? {
        switch policy {
        case .loginKeychain:
            return try backend.read(from: .legacy)
        case .dataProtectionKeychain:
            if let loginValue = try backend.read(from: .legacy) {
                try persistAndVerify(loginValue, to: .dataProtection)
                try backend.delete(from: .legacy)
                try restoreIfNeeded(loginValue, in: .dataProtection)
                return loginValue
            }
            return try backend.read(from: .dataProtection)
        }
    }

    func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete()
            return
        }

        let domain = policy.primaryDomain
        try persistAndVerify(trimmed, to: domain)
        if policy == .dataProtectionKeychain,
           try backend.read(from: .legacy) != nil {
            try backend.delete(from: .legacy)
            try restoreIfNeeded(trimmed, in: .dataProtection)
        }
    }

    func delete() throws {
        try backend.delete(from: policy.primaryDomain)
    }

    private func persistAndVerify(_ value: String, to domain: CredentialStorageDomain) throws {
        try backend.write(value, to: domain)
        guard try backend.read(from: domain) == value else {
            throw CredentialStoreError.persistenceVerificationFailed
        }
    }

    private func restoreIfNeeded(_ expectedValue: String, in domain: CredentialStorageDomain) throws {
        guard try backend.read(from: domain) != expectedValue else { return }
        try persistAndVerify(expectedValue, to: domain)
    }
}
