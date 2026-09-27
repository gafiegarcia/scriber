import Foundation
import os

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
    /// The recording's length in seconds, which sets how long transcribing it may take.
    public let audioDuration: TimeInterval

    public init(
        audioURL: URL,
        apiKey: String,
        languageCode: String,
        noVerbatim: Bool,
        keyterms: [String],
        audioDuration: TimeInterval
    ) {
        self.audioURL = audioURL
        self.apiKey = apiKey
        self.languageCode = languageCode
        self.noVerbatim = noVerbatim
        self.keyterms = keyterms
        self.audioDuration = audioDuration
    }
}

public struct ElevenLabsSubscriptionUsage: Codable, Equatable, Sendable {
    public let tier: String
    public let usedCredits: Int
    public let totalCredits: Int
    public let canExtendCredits: Bool
    public let resetAt: Date?
    public let fetchedAt: Date

    // Known and unfixed: on an account that has topped up, this clamp may read an
    // overage as nothing left — an empty bar and 0% sitting above a caption that
    // says extended usage is available. Whether ElevenLabs reports a top-up by
    // raising `character_limit` or by letting `character_count` climb past it is
    // undocumented, and nobody has seen the response from such an account. A free
    // account cannot produce one, so this stays until someone can look.
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

    /// The tier written as the plan's name, or nil when ElevenLabs sent no tier
    /// to name. ElevenLabs sends a snake_case identifier rather than a label —
    /// `growing_business` — and several of its tiers carry the date they were
    /// introduced, as in `scale_2024_08_10` and `grant_tier_1_2025_07_23`. That
    /// date names the plan's vintage rather than the plan, so a trailing
    /// year-month-day is dropped.
    public var planName: String? {
        var words = tier.split(separator: "_").map(String.init)
        if words.count > 3 {
            let stamp = words.suffix(3)
            let isDate = stamp.allSatisfy { $0.allSatisfy(\.isNumber) } && stamp.first?.count == 4
            if isDate { words.removeLast(3) }
        }
        guard !words.isEmpty else { return nil }
        return words.map(\.capitalized).joined(separator: " ")
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
    case timedOut

    /// Also the caption of the Transcription failed pill, which gives it one
    /// truncated line.
    ///
    /// Measured: the pill is 460 points wide and a caption that carries the row
    /// past that loses the rest to an ellipsis. "ElevenLabs is temporarily
    /// unavailable." wanted 485; the longest that fits is "ElevenLabs rate limit
    /// exceeded" at 448. Length in characters does not predict this — measure a
    /// new caption by adding it to `PillFitAudit`'s samples for a run of
    /// `./scripts/smoke.sh`, which reports the width its row needs.
    ///
    /// Only Scriber's own fixed text needs measuring. Anything carrying
    /// ElevenLabs' words truncates by design, and the three cases the credentials
    /// pill takes — `authentication`, `authorization`, `insufficientCredits` —
    /// draw no caption at all.
    public var errorDescription: String? {
        switch self {
        case .invalidKeyterm(let term): "Invalid keyterm: \(term)"
        case .authentication: "ElevenLabs rejected this API key. Check that it is correct and enabled."
        case .authorization(let message): message
        // A history row says why the dictation failed and stops there. What to do
        // about it is the pill's and the window banner's job, and neither of them
        // is read from a row weeks later.
        case .insufficientCredits: "No ElevenLabs credits left"
        case .invalidRequest(let message): message
        case .rateLimited: "ElevenLabs rate limit exceeded"
        case .serviceUnavailable: "ElevenLabs is unavailable"
        case .http(_, let message): message
        case .network(let message): message
        case .timedOut: "Connection timed out"
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
        case .rateLimited, .serviceUnavailable, .network, .timedOut: true
        case .http(let status, _): status == 408 || status == 429 || status >= 500
        default: false
        }
    }
}

public struct ScribeClient: Sendable {
    /// How long one transcription may take in total, across every attempt and
    /// every backoff between them. A dictation that has not come back inside this
    /// has failed, and its row is retryable.
    ///
    /// 90 seconds for every ten minutes of audio, and never less than 90.
    /// Processing is not what this pays for: Scribe v2 has answered 20 minutes of
    /// the recorder's 64 kbps audio in 18 seconds end to end, and 1 minute in 3.
    /// The headroom is for a slow uplink and the retries, which resend the whole
    /// file each time.
    public static func transcriptionBudget(forAudioDuration duration: TimeInterval) -> TimeInterval {
        max(90, 90 * duration / 600)
    }

    /// How long a transcription request may go without receiving a byte. Scribe
    /// sends nothing while it processes the upload, so this has to outlast the
    /// processing, which grows with the audio: 30 seconds for every ten minutes,
    /// and never less than 30. The longest silence seen was 15 seconds, for 20
    /// minutes of audio.
    static func transcriptionIdleTimeout(forAudioDuration duration: TimeInterval) -> TimeInterval {
        max(30, 30 * duration / 600)
    }

    /// Bounded deliberately. `URLSession.shared` carries a resource timeout of
    /// seven days, so a Wi-Fi that accepts the connection and never answers — a
    /// captive portal, a hotel, a router with no route beyond it — left a
    /// dictation transcribing with no end in sight and its request alive behind.
    ///
    /// One session for every request, so a dictation can reuse the connection
    /// the last one opened. Its resource timeout is only a backstop sized to the
    /// longest recording: a transcription's own budget is enforced by
    /// `withDeadline`, and each request carries its own idle timeout, which
    /// overrides the session's in either direction.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = transcriptionBudget(
            forAudioDuration: RecordingLimit.maximumDuration
        )
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Runs `operation`, and cancels it with `ScribeError.timedOut` if it is still
    /// running at `deadline`. A canceled dictation's request is left to finish,
    /// so this is also what bounds how long one can outlive its pill.
    static func withDeadline<T: Sendable>(
        _ deadline: Date,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                throw ScribeError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ScribeError.timedOut }
            return first
        }
    }

    static let log = Logger(subsystem: "com.gafiegarcia.scriber", category: "dictation")

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
        do { (data, response) = try await Self.session.data(for: request) }
        catch { throw Self.networkError(error) }
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
        do { (data, response) = try await Self.session.data(for: request) }
        catch { throw Self.networkError(error) }
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
        // A key refused over quota is a key that authenticated, so it passes here
        // too. Whether there is credit to dictate with is the subscription
        // reading's to answer, and calling this one invalid is what latched
        // `.invalid` on a credential with nothing wrong with it.
        if Self.exhaustsCredits(statusCode: statusCode, data: data) { return nil }
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
    /// canceled mid-transcription answers false: the attempt already sent is
    /// left to finish because it is billed either way, but a fresh one would
    /// spend the user's credit on a recording they have just abandoned.
    public func transcribe(
        _ input: ScribeRequest,
        run: Int = 0,
        onAttempt: @escaping @Sendable (Int, TimeInterval?) async -> Void,
        permitsRetry: @escaping @Sendable () async -> Bool = { true }
    ) async throws -> ScribeResult {
        let keyterms = try Self.validateKeyterms(input.keyterms)
        let delays: [TimeInterval] = [3, 5]
        var lastError: Error?
        let started = ContinuousClock().now
        let deadline = Date.now.addingTimeInterval(Self.transcriptionBudget(forAudioDuration: input.audioDuration))

        for attempt in 1...3 {
            // Asked again on the way out of the wait, not only on the way in. A
            // cancellation arriving during the backoff has to stop the attempt
            // that wait was for, and the check below has already passed by then.
            if attempt > 1, await permitsRetry() == false { break }
            guard Date.now < deadline else {
                Self.log.notice("transcribe budget spent run=\(run, privacy: .public) attempts=\(attempt - 1, privacy: .public)")
                throw ScribeError.timedOut
            }
            await onAttempt(attempt, nil)
            Self.log.notice("transcribe attempt run=\(run, privacy: .public) n=\(attempt, privacy: .public)")
            do {
                let result = try await Self.withDeadline(deadline) {
                    try await perform(input, keyterms: keyterms, run: run, attempt: attempt)
                }
                Self.log.notice(
                    "transcribe returned run=\(run, privacy: .public) n=\(attempt, privacy: .public) elapsedMs=\(started.elapsedMilliseconds, privacy: .public) empty=\(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, privacy: .public)"
                )
                return result
            } catch {
                lastError = error
                let retryable = (error as? ScribeError)?.retryable ?? isRetryableNetworkError(error)
                Self.log.notice(
                    "transcribe failed run=\(run, privacy: .public) n=\(attempt, privacy: .public) elapsedMs=\(started.elapsedMilliseconds, privacy: .public) retryable=\(retryable, privacy: .public) kind=\(Self.kind(of: error), privacy: .public)"
                )
                guard retryable, attempt < 3, await permitsRetry() else { throw error }
                let delay = delays[attempt - 1]
                // No point waiting out a backoff the budget cannot afford.
                guard Date.now.addingTimeInterval(delay) < deadline else { throw ScribeError.timedOut }
                await onAttempt(attempt, delay)
                // Nothing is in flight during a backoff, so a cancellation
                // arriving inside one has nothing to wait for. Ending the wait
                // then rather than serving it out stops an abandoned run
                // outliving the pill that abandoned it by several seconds.
                guard await waitBeforeRetry(delay, permitsRetry: permitsRetry) else { break }
            }
        }
        throw lastError ?? ScribeError.serviceUnavailable
    }

    /// Names the failure without quoting it. Messages can carry an endpoint or a
    /// server's own prose; a category cannot, and it is what a bug report needs.
    private static func kind(of error: Error) -> String {
        switch error {
        case ScribeError.timedOut: "timedOut"
        case ScribeError.network: "network"
        case ScribeError.rateLimited: "rateLimited"
        case ScribeError.serviceUnavailable: "serviceUnavailable"
        case ScribeError.authentication, ScribeError.authorization: "authentication"
        case ScribeError.insufficientCredits: "insufficientCredits"
        case ScribeError.invalidRequest: "invalidRequest"
        case ScribeError.http(let status, _): "http\(status)"
        default: "other"
        }
    }

    /// Waits in slices so the cancellation is noticed while the wait is running,
    /// not only once it is over. Returns false when the wait was abandoned.
    private func waitBeforeRetry(
        _ delay: TimeInterval,
        permitsRetry: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let slice: TimeInterval = 0.1
        var waited: TimeInterval = 0
        while waited < delay {
            do { try await Task.sleep(for: .seconds(min(slice, delay - waited))) }
            catch { return false }
            waited += slice
            if await permitsRetry() == false { return false }
        }
        return true
    }

    private func perform(
        _ input: ScribeRequest,
        keyterms: [String],
        run: Int,
        attempt: Int
    ) async throws -> ScribeResult {
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

        var request = URLRequest(
            url: endpoint,
            timeoutInterval: Self.transcriptionIdleTimeout(forAudioDuration: input.audioDuration)
        )
        request.httpMethod = "POST"
        request.setValue(input.apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        let timing = TranscriptionTimingLog(run: run, attempt: attempt, audioDuration: input.audioDuration)
        do { (data, response) = try await Self.session.data(for: request, delegate: timing) }
        catch { throw Self.networkError(error) }
        guard let http = response as? HTTPURLResponse else { throw ScribeError.serviceUnavailable }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(data: data) ?? "Transcription failed (\(http.statusCode))."
            Self.log.notice(
                "transcribe refused status=\(http.statusCode, privacy: .public) marker=\(Self.errorMarker(data: data) ?? "none", privacy: .public)"
            )
            if Self.exhaustsCredits(statusCode: http.statusCode, data: data) {
                throw ScribeError.insufficientCredits
            }
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

    /// Says what happened in Scriber's voice. The old text appended Apple's
    /// sentence to one that already said the same thing, and it claimed the user
    /// was offline for a Wi-Fi that routes but never answers.
    static func networkError(_ error: Error) -> ScribeError {
        guard let error = error as? URLError else { return .network("Could not reach ElevenLabs") }
        return switch error.code {
        // Do not: let this drift from the pre-flight refusal in
        // `transcribeCurrentRecord` (`AppCoordinator.swift`), which writes the
        // same sentence; the two disagreed until today. That guard takes every
        // dictation started with no route, leaving this the narrow case where the
        // path monitor is satisfied and the request still cannot connect.
        case .notConnectedToInternet: .network("No internet connection")
        case .networkConnectionLost: .network("The connection was lost")
        case .timedOut: .timedOut
        default: .network("Could not reach ElevenLabs")
        }
    }

    private func isRetryableNetworkError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }

    /// The machine-readable code in an error body, which ElevenLabs carries as
    /// `detail.code` and, on older responses, `detail.status`. A short code word,
    /// never the server's prose, so it is safe to log.
    static func errorMarker(data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] as? [String: Any] else { return nil }
        return detail["code"] as? String ?? detail["status"] as? String
    }

    /// Platform: an exhausted quota comes back as 401, not the 402 ElevenLabs'
    /// error reference documents, and says which it is only in the body. Read from
    /// the status code alone it is indistinguishable from a revoked key — which is
    /// what once marked a working key invalid the moment the credits ran out.
    static func exhaustsCredits(statusCode: Int, data: Data) -> Bool {
        if statusCode == 402 { return true }
        guard statusCode == 401 || statusCode == 403 else { return false }
        if let marker = errorMarker(data: data)?.lowercased(), marker.contains("quota") { return true }
        guard let message = errorMessage(data: data)?.lowercased() else { return false }
        return message.contains("quota") || message.contains("credits remaining")
    }

    static func errorMessage(data: Data) -> String? {
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

/// Logs where one transcription request spent its time — connecting, uploading
/// the recording, and waiting for ElevenLabs to answer — so a slow dictation
/// says whether the network or the service was slow.
private final class TranscriptionTimingLog: NSObject, URLSessionTaskDelegate, Sendable {
    let run: Int
    let attempt: Int
    let audioDuration: TimeInterval

    init(run: Int, attempt: Int, audioDuration: TimeInterval) {
        self.run = run
        self.attempt = attempt
        self.audioDuration = audioDuration
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        func ms(_ start: Date?, _ end: Date?) -> Int {
            guard let start, let end else { return -1 }
            return Int(end.timeIntervalSince(start) * 1000)
        }
        ScribeClient.log.notice(
            "transcribe timing run=\(self.run, privacy: .public) n=\(self.attempt, privacy: .public) audioMs=\(Int(self.audioDuration * 1000), privacy: .public) bytes=\(transaction.countOfRequestBodyBytesSent, privacy: .public) reused=\(transaction.isReusedConnection, privacy: .public) connectMs=\(ms(transaction.connectStartDate, transaction.connectEndDate), privacy: .public) uploadMs=\(ms(transaction.requestStartDate, transaction.requestEndDate), privacy: .public) waitMs=\(ms(transaction.requestEndDate, transaction.responseStartDate), privacy: .public) protocol=\(transaction.networkProtocolName ?? "none", privacy: .public)"
        )
    }
}
