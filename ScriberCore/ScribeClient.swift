import Foundation

// Direct ElevenLabs Scribe v2 client shared with the app target.

public struct ScribeResult: Decodable, Sendable {
    public let text: String
    public let languageCode: String?
    public let languageProbability: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case languageProbability = "language_probability"
    }
}

public struct ScribeRequest: Sendable {
    public let audioURL: URL
    public let apiKey: String
    public let languageCode: String
    public let noVerbatim: Bool
    public let keyterms: [String]

    public init(audioURL: URL, apiKey: String, languageCode: String, noVerbatim: Bool, keyterms: [String]) {
        self.audioURL = audioURL
        self.apiKey = apiKey
        self.languageCode = languageCode
        self.noVerbatim = noVerbatim
        self.keyterms = keyterms
    }
}

public struct ElevenLabsSubscriptionUsage: Codable, Equatable, Sendable {
    public let tier: String
    public let usedCredits: Int
    public let totalCredits: Int
    public let canExtendCredits: Bool
    public let resetAt: Date?
    public let fetchedAt: Date

    public var remainingCredits: Int { max(0, totalCredits - usedCredits) }
    public var shouldBlockDictation: Bool {
        remainingCredits == 0 && !canExtendCredits
    }

    /// Remaining credits as a whole percentage, or nil when there is no total to
    /// measure against. 0 and 100 are reserved for genuinely empty and genuinely
    /// full, so a sliver either way rounds to 1 and 99 instead of reading as the
    /// endpoint it has not reached.
    public var remainingPercentage: Int? {
        guard totalCredits > 0 else { return nil }
        if remainingCredits == 0 { return 0 }
        if remainingCredits >= totalCredits { return 100 }
        let rounded = Int((Double(remainingCredits) / Double(totalCredits) * 100).rounded())
        return min(99, max(1, rounded))
    }

    public init(
        tier: String,
        usedCredits: Int,
        totalCredits: Int,
        canExtendCredits: Bool,
        resetAt: Date?,
        fetchedAt: Date = .now
    ) {
        self.tier = tier
        self.usedCredits = usedCredits
        self.totalCredits = totalCredits
        self.canExtendCredits = canExtendCredits
        self.resetAt = resetAt
        self.fetchedAt = fetchedAt
    }

    enum CodingKeys: String, CodingKey {
        case tier
        case usedCredits = "character_count"
        case totalCredits = "character_limit"
        case canExtendCharacterLimit = "can_extend_character_limit"
        case maxCreditLimitExtension = "max_credit_limit_extension"
        case resetAt = "next_character_count_reset_unix"
        case fetchedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tier = try container.decode(String.self, forKey: .tier)
        usedCredits = try container.decode(Int.self, forKey: .usedCredits)
        totalCredits = try container.decode(Int.self, forKey: .totalCredits)
        let legacyCanExtend = try container.decodeIfPresent(Bool.self, forKey: .canExtendCharacterLimit) ?? false
        let extensionAmount = try? container.decode(Int.self, forKey: .maxCreditLimitExtension)
        let extensionLabel = try? container.decode(String.self, forKey: .maxCreditLimitExtension)
        canExtendCredits = legacyCanExtend || (extensionAmount ?? 0) > 0 || extensionLabel == "unlimited"
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .resetAt) {
            resetAt = Date(timeIntervalSince1970: timestamp)
        } else {
            resetAt = nil
        }
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .now
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tier, forKey: .tier)
        try container.encode(usedCredits, forKey: .usedCredits)
        try container.encode(totalCredits, forKey: .totalCredits)
        try container.encode(canExtendCredits, forKey: .canExtendCharacterLimit)
        try container.encodeIfPresent(resetAt?.timeIntervalSince1970, forKey: .resetAt)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }
}

public struct APIKeyValidationResult: Sendable {
    public let subscriptionUsage: ElevenLabsSubscriptionUsage?
    public let subscriptionUsageUnavailable: Bool
    public let subscriptionUsageAccessDenied: Bool
}

public enum ScribeError: LocalizedError, Sendable {
    case invalidKeyterm(String)
    case authentication
    case authorization(String)
    case insufficientCredits
    case invalidRequest(String)
    case rateLimited
    case serviceUnavailable
    case http(Int, String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKeyterm(let term): "Invalid keyterm: \(term)"
        case .authentication: "ElevenLabs rejected this API key. Check that it is correct and enabled."
        case .authorization(let message): message
        case .insufficientCredits: "Your ElevenLabs credits are exhausted. Add credits or wait for your quota to reset."
        case .invalidRequest(let message): message
        case .rateLimited: "ElevenLabs rate limit exceeded."
        case .serviceUnavailable: "ElevenLabs is temporarily unavailable."
        case .http(_, let message): message
        case .network(let message): message
        }
    }

    public var invalidatesAPIKey: Bool {
        switch self {
        case .authentication, .authorization: true
        default: false
        }
    }

    public var retryable: Bool {
        switch self {
        case .rateLimited, .serviceUnavailable, .network: true
        case .http(let status, _): status == 408 || status == 429 || status >= 500
        default: false
        }
    }
}

public struct ScribeClient: Sendable {
    private let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    private let subscriptionEndpoint = URL(string: "https://api.elevenlabs.io/v1/user/subscription")!
    private let validationEndpoint = URL(
        string: "https://api.elevenlabs.io/v1/speech-to-text/transcripts/00000000-0000-0000-0000-000000000000"
    )!

    public init() {}

    public static func validateKeyterms(_ keyterms: [String]) throws -> [String] {
        guard keyterms.count <= 1_000 else {
            throw ScribeError.invalidRequest("Scribe accepts at most 1,000 keyterms.")
        }
        let unsupported = CharacterSet(charactersIn: "<>{}[]\\")
        return try keyterms.compactMap { value in
            let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if term.isEmpty { return nil }
            guard term.count < 50,
                  term.split(whereSeparator: { $0.isWhitespace }).count <= 5,
                  term.rangeOfCharacter(from: unsupported) == nil else {
                throw ScribeError.invalidKeyterm(term)
            }
            return term
        }
    }

    public func validateAPIKey(_ apiKey: String) async throws -> APIKeyValidationResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScribeError.authentication }

        let subscriptionUsage: ElevenLabsSubscriptionUsage?
        let subscriptionUsageAccessDenied: Bool
        do {
            subscriptionUsage = try await fetchSubscriptionUsage(trimmed)
            subscriptionUsageAccessDenied = false
        } catch let error as ScribeError {
            subscriptionUsage = nil
            subscriptionUsageAccessDenied = error.invalidatesAPIKey
        } catch {
            // User/subscription access has its own optional API-key scope. The STT
            // check below remains authoritative for whether Scriber can dictate.
            subscriptionUsage = nil
            subscriptionUsageAccessDenied = false
        }

        // Query a deliberately nonexistent transcript so validation exercises the
        // Speech-to-Text scope without uploading audio or consuming API credits.
        var request = URLRequest(url: validationEndpoint, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(trimmed, forHTTPHeaderField: "xi-api-key")

        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ScribeError.network("Could not reach ElevenLabs: \(error.localizedDescription)") }
        guard let http = response as? HTTPURLResponse else { throw ScribeError.serviceUnavailable }
        if let error = Self.apiKeyValidationError(statusCode: http.statusCode, data: data) { throw error }
        return APIKeyValidationResult(
            subscriptionUsage: subscriptionUsage,
            subscriptionUsageUnavailable: subscriptionUsage == nil,
            subscriptionUsageAccessDenied: subscriptionUsageAccessDenied
        )
    }

    public func fetchSubscriptionUsage(_ apiKey: String) async throws -> ElevenLabsSubscriptionUsage {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScribeError.authentication }
        var request = URLRequest(url: subscriptionEndpoint, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(trimmed, forHTTPHeaderField: "xi-api-key")

        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ScribeError.network("Could not reach ElevenLabs: \(error.localizedDescription)") }
        guard let http = response as? HTTPURLResponse else { throw ScribeError.serviceUnavailable }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.responseError(statusCode: http.statusCode, data: data, fallback: "Could not load credit usage")
        }
        return try Self.decodeSubscriptionUsage(data)
    }

    static func apiKeyValidationError(statusCode: Int, data: Data) -> ScribeError? {
        // The sentinel transcript must not exist. These responses mean the request
        // passed authentication and Speech-to-Text authorization before lookup.
        guard !(200..<300).contains(statusCode), ![400, 404, 422].contains(statusCode) else { return nil }
        switch statusCode {
        case 401:
            return .authentication
        case 403:
            return .authorization(
                "ElevenLabs denied this key’s access. Check its endpoint scope and IP allowlist."
            )
        case 429:
            return .rateLimited
        case 500...599:
            return .serviceUnavailable
        default:
            let message = Self.errorMessage(data: data) ?? "API-key check failed (\(statusCode))."
            return .http(statusCode, message)
        }
    }

    /// `permitsRetry` is asked before every attempt after the first. A dictation
    /// cancelled mid-transcription answers false: the attempt already sent is
    /// left to finish because it is billed either way, but a fresh one would
    /// spend the user's credit on a recording they have just abandoned.
    public func transcribe(
        _ input: ScribeRequest,
        onAttempt: @escaping @Sendable (Int, TimeInterval?) async -> Void,
        permitsRetry: @escaping @Sendable () async -> Bool = { true }
    ) async throws -> ScribeResult {
        let keyterms = try Self.validateKeyterms(input.keyterms)
        let delays: [TimeInterval] = [3, 5]
        var lastError: Error?

        for attempt in 1...3 {
            await onAttempt(attempt, nil)
            do {
                return try await perform(input, keyterms: keyterms)
            } catch {
                lastError = error
                let retryable = (error as? ScribeError)?.retryable ?? isRetryableNetworkError(error)
                guard retryable, attempt < 3, await permitsRetry() else { throw error }
                let delay = delays[attempt - 1]
                await onAttempt(attempt, delay)
                try await Task.sleep(for: .seconds(delay))
            }
        }
        throw lastError ?? ScribeError.serviceUnavailable
    }

    private func perform(_ input: ScribeRequest, keyterms: [String]) async throws -> ScribeResult {
        let audio: Data
        do { audio = try Data(contentsOf: input.audioURL) }
        catch { throw ScribeError.invalidRequest("The recording could not be read.") }

        let boundary = "Scriber-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        field("model_id", "scribe_v2")
        field("timestamps_granularity", "none")
        field("diarize", "false")
        field("tag_audio_events", "false")
        field("no_verbatim", input.noVerbatim ? "true" : "false")
        if input.languageCode != "auto" { field("language_code", input.languageCode) }
        for term in keyterms { field("keyterms", term) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.m4a\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue(input.apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ScribeError.network("Could not reach ElevenLabs: \(error.localizedDescription)") }
        guard let http = response as? HTTPURLResponse else { throw ScribeError.serviceUnavailable }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(data: data) ?? "Transcription failed (\(http.statusCode))."
            switch http.statusCode {
            case 401, 403: throw ScribeError.authentication
            case 402: throw ScribeError.insufficientCredits
            case 400, 413: throw ScribeError.invalidRequest(message)
            case 429: throw ScribeError.rateLimited
            case 500...599: throw ScribeError.serviceUnavailable
            default: throw ScribeError.http(http.statusCode, message)
            }
        }
        return try Self.decodeResponse(data)
    }

    static func decodeResponse(_ data: Data) throws -> ScribeResult {
        try JSONDecoder().decode(ScribeResult.self, from: data)
    }

    static func decodeSubscriptionUsage(_ data: Data) throws -> ElevenLabsSubscriptionUsage {
        try JSONDecoder().decode(ElevenLabsSubscriptionUsage.self, from: data)
    }

    private func isRetryableNetworkError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }

    private static func errorMessage(data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let detail = object["detail"] as? String { return detail }
        if let detail = object["detail"] as? [String: Any], let message = detail["message"] as? String { return message }
        return object["message"] as? String ?? object["error"] as? String
    }

    private static func responseError(statusCode: Int, data: Data, fallback: String) -> ScribeError {
        switch statusCode {
        case 401: .authentication
        case 402: .insufficientCredits
        case 403: .authorization(
            Self.errorMessage(data: data) ?? "ElevenLabs denied access to this account information."
        )
        case 429: .rateLimited
        case 500...599: .serviceUnavailable
        default: .http(statusCode, Self.errorMessage(data: data) ?? "\(fallback) (\(statusCode)).")
        }
    }
}
