import CryptoKit
import Foundation
import GobblCore
import Observation

/// Talks to Gobbl's AI service (the ai.xeve.io Worker, which holds the
/// OpenRouter key). No secret lives in the app: each install has its own
/// Ed25519 key in the Keychain, registers once, and signs every request.
/// Everything sent is also appended to a local log the user can read.
@MainActor @Observable
final class AIClient {
    static let shared = AIClient()

    enum AIError: LocalizedError, Equatable {
        case notRegistered
        case quota(resetsAt: String?)
        case paused
        case server(String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notRegistered: "Turn on AI in Settings first."
            case .quota: "That's today's AI allowance. It resets tomorrow."
            case .paused: "The AI service is taking a short break. Try again later."
            case .server(let m): m
            case .network(let m): m
            }
        }
    }

    private(set) var installID: String? = UserDefaults.standard.string(forKey: "aiInstallID")
    private(set) var remainingToday: Int?

    var isRegistered: Bool { installID != nil }

    /// Just language and region ("en-IN"). Full BCP-47 can carry extensions
    /// like "en-US-u-rg-inzzzz" (region set separately from language), which the service rejects.
    nonisolated static var locale: String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        guard let region = Locale.current.region?.identifier, region.count == 2 else { return language }
        return "\(language)-\(region)"
    }

    /// The last error in full, for Settings (the notch only has room for a few words).
    private(set) var lastError: String?

    var baseURL: URL {
        URL(string: UserDefaults.standard.string(forKey: "aiBaseURL") ?? "https://ai.xeve.io") ?? URL(string: "https://ai.xeve.io")!
    }

    static let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Gobbl/ai-requests.jsonl")

    // MARK: Identity

    private var signingKey: Curve25519.Signing.PrivateKey {
        if let raw = Keychain.data("installKey"), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            return key
        }
        let key = Curve25519.Signing.PrivateKey()
        Keychain.set(key.rawRepresentation, for: "installKey")
        return key
    }

    /// One-time registration. `turnstileToken` comes from the verification sheet.
    func register(turnstileToken: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "publicKey": signingKey.publicKey.rawRepresentation.base64EncodedString(),
            "turnstileToken": turnstileToken,
            "appVersion": Updater.versionString,
        ])
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/register"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 201 for a new install, 200 when this key was already registered.
        guard (200..<300).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["installId"] as? String else {
            throw AIError.server(Self.message(from: data) ?? "Couldn't turn on AI (\(status)).")
        }
        installID = id
        UserDefaults.standard.set(id, forKey: "aiInstallID")
        await refreshQuota()
    }

    func signOut() {
        installID = nil
        UserDefaults.standard.removeObject(forKey: "aiInstallID")
        Keychain.delete("installKey")
    }

    // MARK: Requests

    func refreshQuota() async {
        guard let request = try? signedRequest("GET", path: "/v1/quota", body: Data()),
              let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        remainingToday = json["actionsRemaining"] as? Int
    }

    /// Streams text deltas from a task endpoint ("/v1/write", "/v1/cleanup").
    func stream(_ path: String, body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    guard isRegistered else { throw AIError.notRegistered }
                    let data = try JSONSerialization.data(withJSONObject: body)
                    log(path: path, body: data)
                    let request = try signedRequest("POST", path: path, body: data)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var errorBody = Data()
                        for try await byte in bytes { errorBody.append(byte); if errorBody.count > 4096 { break } }
                        throw Self.error(status: status, data: errorBody)
                    }
                    var parser = SSEParser()
                    var pending = Data()
                    for try await byte in bytes {
                        pending.append(byte)
                        guard byte == 0x0A else { continue }
                        for event in parser.feed(String(decoding: pending, as: UTF8.self)) {
                            switch event.event {
                            case "delta":
                                if let text = Self.json(event.data)?["text"] as? String { continuation.yield(text) }
                            case "done":
                                continuation.finish()
                                Task { await self.refreshQuota() }
                                return
                            case "error":
                                throw AIError.server(Self.json(event.data)?["message"] as? String ?? "The AI hit a snag.")
                            default:
                                break
                            }
                        }
                        pending.removeAll(keepingCapacity: true)
                    }
                    // Closed without "done" or "error": the answer may be cut off.
                    throw AIError.server("The AI stopped before finishing. Try again.")
                } catch let error as AIError {
                    lastError = "\(Self.timeStamp()) \(path): \(error.errorDescription ?? "")"
                    continuation.finish(throwing: error)
                } catch {
                    lastError = "\(Self.timeStamp()) \(path): \(error.localizedDescription)"
                    continuation.finish(throwing: AIError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Collects a whole streamed response.
    func complete(_ path: String, body: [String: Any]) async throws -> String {
        var text = ""
        for try await delta in stream(path, body: body) { text += delta }
        return text
    }

    private func signedRequest(_ method: String, path: String, body: Data) throws -> URLRequest {
        guard let installID else { throw AIError.notRegistered }
        let timestamp = Int(Date().timeIntervalSince1970)
        var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        if method != "GET" { request.httpBody = body }
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(installID, forHTTPHeaderField: "X-Gobbl-Install")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-Gobbl-Timestamp")
        request.setValue(try RequestSigning.sign(signingKey, method: method, path: path, timestamp: timestamp, body: body),
                         forHTTPHeaderField: "X-Gobbl-Signature")
        return request
    }

    // MARK: Helpers

    /// Transparency: exactly what left the Mac, and when.
    private func log(path: String, body: Data) {
        let entry: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "endpoint": path,
                                    "body": (try? JSONSerialization.jsonObject(with: body)) ?? [:]]
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        let url = Self.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    private static func json(_ s: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
    }

    private static func message(from data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
    }

    private static func error(status: Int, data: Data) -> AIError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        switch status {
        case 401, 403: return .notRegistered
        case 429 where json?["error"] as? String == "quota": return .quota(resetsAt: json?["resetsAt"] as? String)
        case 429: return .server("Slow down a little and try again.")
        case 503: return .paused
        case 413: return .server("That's too much text for one go.")
        case 400 where json?["error"] as? String == "empty_input": return .server("There's nothing to work with here.")
        default:
            let code = json?["error"] as? String
            return .server(json?["message"] as? String ?? "The AI service returned \(status)\(code.map { " (\($0))" } ?? "").")
        }
    }

    private static func timeStamp() -> String {
        Date().formatted(date: .omitted, time: .shortened)
    }
}
