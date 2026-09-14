import CryptoKit
import Foundation

/// Request signing for the ai.xeve.io Worker. Every request after
/// registration carries the install id, a unix timestamp and an Ed25519
/// signature over
///
///     METHOD \n PATH \n TIMESTAMP \n sha256hex(BODY)
///
/// made with the install's private key, which never leaves the Keychain.
public enum RequestSigning {
    public static func canonical(method: String, path: String, timestamp: Int, body: Data) -> String {
        let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return "\(method.uppercased())\n\(path)\n\(timestamp)\n\(hash)"
    }

    public static func sign(_ key: Curve25519.Signing.PrivateKey, method: String, path: String,
                            timestamp: Int, body: Data) throws -> String {
        let message = Data(canonical(method: method, path: path, timestamp: timestamp, body: body).utf8)
        return try key.signature(for: message).base64EncodedString()
    }
}

public struct SSEEvent: Equatable, Sendable {
    public var event: String
    public var data: String

    public init(event: String, data: String) {
        self.event = event
        self.data = data
    }
}

/// Incremental server-sent-events parser: feed it chunks as they arrive, get
/// complete events back. Comment lines (": …") are ignored.
public struct SSEParser: Sendable {
    private var buffer = ""
    private var event = "message"
    private var data: [String] = []

    public init() {}

    public mutating func feed(_ chunk: String) -> [SSEEvent] {
        buffer += chunk
        var out: [SSEEvent] = []
        // "\r\n" is a single Character in Swift, so match both line endings.
        while let newline = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) {
            let line = String(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.isEmpty {
                if !data.isEmpty { out.append(SSEEvent(event: event, data: data.joined(separator: "\n"))) }
                event = "message"
                data = []
            } else if line.hasPrefix(":") {
                continue
            } else if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst(5)
                if value.hasPrefix(" ") { value = value.dropFirst() }
                data.append(String(value))
            }
        }
        return out
    }
}

/// What the focused text field holds when the Gobbl key is tapped.
public struct FieldSnapshot: Equatable, Sendable {
    public var value: String
    public var selection: String
    public var appName: String
    public var bundleID: String
    public var windowTitle: String
    public var url: String?
    /// Text around the field (the conversation or page), for drafting in context.
    public var nearbyText: String

    public init(value: String, selection: String = "", appName: String = "", bundleID: String = "",
                windowTitle: String = "", url: String? = nil, nearbyText: String = "") {
        self.value = value
        self.selection = selection
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.url = url
        self.nearbyText = nearbyText
    }
}

/// What a tap of the Gobbl key should do with the field.
public enum WriteMode: String, Codable, Sendable {
    /// The field holds an instruction ("reply saying yes but next week"): replace it with the result.
    case instruction
    /// Text is selected: rewrite just that.
    case rewrite
    /// Empty field: draft something from the surrounding context.
    case draft
    /// "/g question": answer it in place.
    case answer

    public static func `for`(_ s: FieldSnapshot) -> WriteMode {
        if !s.selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .rewrite }
        let value = s.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("/g") { return .answer }
        return value.isEmpty ? .draft : .instruction
    }

    /// The text to send for this mode.
    public func text(from s: FieldSnapshot) -> String {
        switch self {
        case .rewrite: s.selection
        case .answer: String(s.value.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(2)).trimmingCharacters(in: .whitespaces)
        case .instruction: s.value
        case .draft: ""
        }
    }

    /// Whether the result replaces the whole field (vs. the selection or the caret).
    public var replacesWholeField: Bool { self == .instruction || self == .answer }
}
