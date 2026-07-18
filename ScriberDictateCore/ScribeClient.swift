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

public enum ScribeError: LocalizedError, Sendable {
    case invalidKeyterm(String)
    case authentication
    case invalidRequest(String)
    case rateLimited
    case serviceUnavailable
    case emptyTranscript
    case http(Int, String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKeyterm(let term): "Invalid keyterm: \(term)"
        case .authentication: "ElevenLabs authentication failed. Check the API key in Settings."
        case .invalidRequest(let message): message
        case .rateLimited: "ElevenLabs rate limit exceeded."
        case .serviceUnavailable: "ElevenLabs is temporarily unavailable."
        case .emptyTranscript: "No speech was detected."
        case .http(_, let message): message
        case .network(let message): message
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

    public func transcribe(
        _ input: ScribeRequest,
        onAttempt: @escaping @Sendable (Int, TimeInterval?) async -> Void
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
                guard retryable, attempt < 3 else { throw error }
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

        let boundary = "ScriberDictate-\(UUID().uuidString)"
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
            case 400, 413: throw ScribeError.invalidRequest(message)
            case 429: throw ScribeError.rateLimited
            case 500...599: throw ScribeError.serviceUnavailable
            default: throw ScribeError.http(http.statusCode, message)
            }
        }
        let result = try JSONDecoder().decode(ScribeResult.self, from: data)
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScribeError.emptyTranscript
        }
        return result
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
}
