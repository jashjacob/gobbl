import Foundation

/// Adds and removes Gobbl's MCP server in AI apps' config files. Our entry is
/// the one named "gobbl", or any whose command contains `gobbl-mcp`. JSON is
/// edited in place, keeping key order and the file's indent; files with
/// comments or trailing commas (JSONC) are refused rather than rewritten.
extension AgentHookConfig {
    public static let mcpName = "gobbl"
    public static let mcpMarker = "gobbl-mcp"

    public enum MCPConfigError: Error, Equatable {
        /// Comments or trailing commas: add Gobbl by hand (or through the app's CLI).
        case jsonc
        case invalidJSON
        case notJSONObject
    }

    public enum MCPEntryStyle: Equatable, Sendable {
        /// `{command, args}`: Claude Desktop, Windsurf, Gemini, LM Studio.
        case plain
        /// `{type: "stdio", command, args}`: Claude Code, Cursor, VS Code.
        case typed
        /// `{command, args, env}`: Zed.
        case zed
    }

    public static func mcpEntry(_ style: MCPEntryStyle, command: String) -> OrderedJSON {
        var members: [(key: String, value: OrderedJSON)] = []
        if style == .typed { members.append(("type", .string("stdio"))) }
        members.append(("command", .string(command)))
        members.append(("args", .array([])))
        if style == .zed { members.append(("env", .object([]))) }
        return .object(members)
    }

    // MARK: JSON

    public static func installMCP(into data: Data?, key: String, entry: OrderedJSON) throws -> Data {
        let file = try parseMCP(data)
        var root = file.root
        var servers = try container(root, key)
        servers.removeAll { $0.key != mcpName && isOurMCP($0.key, $0.value) }
        var object = OrderedJSON.object(servers)
        object.set(mcpName, entry)
        root.set(key, object)
        return output(root, file)
    }

    public static func uninstallMCP(from data: Data?, key: String) throws -> Data {
        let file = try parseMCP(data)
        var root = file.root
        guard root[key] != nil else { return data ?? Data() }
        var servers = try container(root, key)
        servers.removeAll { isOurMCP($0.key, $0.value) }
        root.set(key, .object(servers))
        return output(root, file)
    }

    /// Our entry's command ("" if it has none), or nil when Gobbl isn't there. Reads JSONC too.
    public static func mcpCommand(_ data: Data?, key: String) -> String? {
        guard let data, let root = (try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])) as? [String: Any],
              let servers = root[key] as? [String: Any] else { return nil }
        func command(_ value: Any?) -> String? {
            let entry = value as? [String: Any]
            return entry?["command"] as? String ?? (entry?["command"] as? [String: Any])?["path"] as? String
        }
        if let ours = servers[mcpName] { return command(ours) ?? "" }
        return servers.values.lazy.compactMap(command).first { $0.contains(mcpMarker) }
    }

    static func isOurMCP(_ name: String, _ value: OrderedJSON) -> Bool {
        if name == mcpName { return true }
        let command = value["command"]?.stringValue ?? value["command"]?["path"]?.stringValue ?? ""
        return command.contains(mcpMarker)
    }

    private struct JSONFile {
        var root: OrderedJSON
        var indent: String
        var trailingNewline: Bool
    }

    private static func parseMCP(_ data: Data?) throws -> JSONFile {
        let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return JSONFile(root: .object([]), indent: "  ", trailingNewline: true) }
        let root: OrderedJSON
        do {
            root = try OrderedJSON.parse(text)
        } catch OrderedJSON.ParseError.jsonc {
            throw MCPConfigError.jsonc
        } catch {
            throw MCPConfigError.invalidJSON
        }
        guard root.members != nil else { throw MCPConfigError.notJSONObject }
        return JSONFile(root: root, indent: OrderedJSON.detectIndent(text), trailingNewline: text.hasSuffix("\n"))
    }

    private static func container(_ root: OrderedJSON, _ key: String) throws -> [(key: String, value: OrderedJSON)] {
        guard let value = root[key] else { return [] }
        guard let members = value.members else { throw MCPConfigError.notJSONObject }
        return members
    }

    private static func output(_ root: OrderedJSON, _ file: JSONFile) -> Data {
        Data((root.serialized(indent: file.indent) + (file.trailingNewline ? "\n" : "")).utf8)
    }

    // MARK: Codex (TOML)

    public static let codexMCPComment = "# added by Gobbl"

    public static func codexMCPBlock(command: String) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\(codexMCPComment)\n[mcp_servers.gobbl]\ncommand = \"\(escaped)\"\nargs = []\n"
    }

    /// config.toml with Gobbl's `[mcp_servers.gobbl]` block at the end (replacing any earlier one).
    public static func installCodexMCP(into text: String, command: String) -> String {
        var base = uninstallCodexMCP(from: text)
        while base.last?.isWhitespace == true { base.removeLast() }
        return (base.isEmpty ? "" : base + "\n\n") + codexMCPBlock(command: command)
    }

    public static func uninstallCodexMCP(from text: String) -> String {
        var out: [TOMLBlock] = []
        var removed = false
        for block in tomlBlocks(text) {
            guard isOurTOML(block) else {
                out.append(block)
                continue
            }
            removed = true
            // Our "# added by Gobbl" comment sits at the end of the block before ours.
            if var previous = out.popLast() {
                previous.trimTrailingBlanks()
                if previous.lines.last?.trimmingCharacters(in: .whitespaces) == codexMCPComment { previous.lines.removeLast() }
                previous.trimTrailingBlanks()
                if !previous.lines.isEmpty { previous.lines.append("") }
                out.append(previous)
            }
        }
        guard removed else { return text }
        var joined = out.flatMap(\.lines).joined(separator: "\n")
        while joined.contains("\n\n\n") { joined = joined.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        while joined.first?.isNewline == true { joined.removeFirst() }
        while joined.last?.isWhitespace == true { joined.removeLast() }
        return joined.isEmpty ? "" : joined + "\n"
    }

    /// Our block's command ("" if it has none), or nil when Gobbl isn't there.
    public static func codexMCPCommand(_ text: String) -> String? {
        guard let block = tomlBlocks(text).first(where: isOurTOML) else { return nil }
        guard let line = block.lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("command") }),
              let eq = line.firstIndex(of: "=") else { return "" }
        return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private struct TOMLBlock {
        var header: String?
        var lines: [String]

        mutating func trimTrailingBlanks() {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        }
    }

    private static let tomlHeader = try! NSRegularExpression(pattern: #"^\s*\[\[?\s*([A-Za-z0-9_\-."' ]+?)\s*\]\]?\s*(#.*)?$"#)

    /// The file split at each [table] header; the first block holds top-level keys.
    private static func tomlBlocks(_ text: String) -> [TOMLBlock] {
        var blocks = [TOMLBlock(header: nil, lines: [])]
        for line in text.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            if let m = tomlHeader.firstMatch(in: line, range: range), let name = Range(m.range(at: 1), in: line) {
                blocks.append(TOMLBlock(header: String(line[name]).replacingOccurrences(of: " ", with: ""), lines: [line]))
            } else {
                blocks[blocks.count - 1].lines.append(line)
            }
        }
        return blocks
    }

    private static func isOurTOML(_ block: TOMLBlock) -> Bool {
        guard let header = block.header else { return false }
        for base in ["mcp_servers.gobbl", "mcp_servers.\"gobbl\"", "mcp_servers.'gobbl'"] where header == base || header.hasPrefix(base + ".") {
            return true
        }
        return header.hasPrefix("mcp_servers.")
            && block.lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("command") && $0.contains(mcpMarker) }
    }
}
