import Foundation

/// JSON-RPC 2.0 for `gobbl-mcp`, one message per line. Dual-era: answers the
/// legacy `initialize` handshake (2024-11-05 … 2025-11-25) and stateless
/// 2026-07-28 requests that carry their protocol version in `_meta`.
public final class MCPServer: @unchecked Sendable {
    public static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    public static let modernVersions = ["2026-07-28"]
    public static var supportedVersions: [String] { modernVersions + legacyVersions }
    static let versionMetaKey = "io.modelcontextprotocol/protocolVersion"
    static let serverInfoMetaKey = "io.modelcontextprotocol/serverInfo"

    public enum Code {
        public static let parseError = -32700
        public static let invalidRequest = -32600
        public static let methodNotFound = -32601
        public static let invalidParams = -32602
        public static let unsupportedVersion = -32022
    }

    public static let instructions = """
    Gobbl is the user's private memory on their Mac: what they read and wrote on screen (chats, mail, web pages, \
    documents), the to-dos Gobbl noticed, and the people and projects in them. Use search_memory to find something \
    they saw or said, get_day and recent_activity for what they did, who_is, get_person and get_project for people \
    and projects, and list_todos for open tasks. Results cite their source as "App · chat or site · time", in the \
    user's local time. Only add reminders or mark to-dos done when the user asks.
    """

    private let version: String
    private let tools: MCPTools
    private let onToolCall: ((String) -> Void)?

    /// `onToolCall` hears the name of each tool called, for the request log.
    public init(version: String, tools: MCPTools, onToolCall: ((String) -> Void)? = nil) {
        self.version = version
        self.tools = tools
        self.onToolCall = onToolCall
    }

    private var serverInfo: [String: Any] { ["name": "gobbl", "title": "Gobbl", "version": version] }
    private var capabilities: [String: Any] { ["tools": ["listChanged": false]] }

    /// One incoming line in, one line out (nil for notifications and blank lines).
    public func handle(line: String) -> String? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let message = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else {
            return encode(Self.error(nil, Code.parseError, "Parse error"))
        }
        if let batch = message as? [Any] {
            guard !batch.isEmpty else { return encode(Self.error(nil, Code.invalidRequest, "Empty batch")) }
            let replies = batch.compactMap(respond)
            return replies.isEmpty ? nil : encode(replies)
        }
        return respond(to: message).flatMap(encode)
    }

    private func respond(to message: Any) -> [String: Any]? {
        guard let msg = message as? [String: Any] else { return Self.error(nil, Code.invalidRequest, "Invalid request") }
        guard let method = msg["method"] as? String else {
            // A response to a request we never send: ignore it.
            if msg["result"] != nil || msg["error"] != nil { return nil }
            return Self.error(msg["id"], Code.invalidRequest, "Invalid request")
        }
        // Notifications (notifications/initialized, cancelled…) get no reply.
        guard let id = msg["id"] else { return nil }
        guard msg["jsonrpc"] as? String == "2.0" else { return Self.error(id, Code.invalidRequest, "jsonrpc must be \"2.0\"") }
        let params = msg["params"] as? [String: Any] ?? [:]

        let requested = (params["_meta"] as? [String: Any])?[Self.versionMetaKey] as? String
        if let requested, method != "initialize", !Self.supportedVersions.contains(requested) {
            return Self.error(id, Code.unsupportedVersion, "Unsupported protocol version",
                              data: ["supported": Self.supportedVersions, "requested": requested])
        }
        let modern = requested.map(Self.modernVersions.contains) ?? false

        var result: [String: Any]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            result = ["protocolVersion": Self.legacyVersions.contains(asked) ? asked : Self.legacyVersions[0],
                      "capabilities": capabilities, "serverInfo": serverInfo, "instructions": Self.instructions]
        case "server/discover":
            result = ["supportedVersions": Self.supportedVersions, "capabilities": capabilities,
                      "instructions": Self.instructions, "ttlMs": 3_600_000, "cacheScope": "private"]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": MCPTools.definitions]
            if modern {
                result["ttlMs"] = 3_600_000
                result["cacheScope"] = "private"
            }
        case "tools/call":
            guard let name = params["name"] as? String else { return Self.error(id, Code.invalidParams, "Missing tool name") }
            guard let arguments = (params["arguments"] ?? [String: Any]()) as? [String: Any] else {
                return Self.error(id, Code.invalidParams, "arguments must be an object")
            }
            guard let r = tools.call(name, arguments: arguments) else { return Self.error(id, Code.invalidParams, "Unknown tool: \(name)") }
            onToolCall?(name)
            result = ["content": [["type": "text", "text": r.text]], "isError": r.isError]
        default:
            return Self.error(id, Code.methodNotFound, "Method not found: \(method)")
        }
        if modern || method == "server/discover" {
            result["resultType"] = "complete"
            result["_meta"] = [Self.serverInfoMetaKey: serverInfo]
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(_ id: Any?, _ code: Int, _ message: String, data: Any? = nil) -> [String: Any] {
        var e: [String: Any] = ["code": code, "message": message]
        if let data { e["data"] = data }
        return ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": e]
    }

    /// Single-line JSON: string newlines are escaped, so stdout stays one message per line.
    private func encode(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
