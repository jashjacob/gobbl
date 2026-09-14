import Foundation

/// An AI app Gobbl can connect its MCP server to: where its config lives,
/// how to spot it, and its CLI if it has one.
public struct MCPClient: Identifiable, Equatable, Sendable {
    public enum Format: Equatable, Sendable {
        case json(key: String, style: AgentHookConfig.MCPEntryStyle)
        case codexTOML
    }

    public let id: String
    public let name: String
    /// Relative to home. With several, the first whose folder exists wins, else the last.
    public let configPaths: [String]
    /// Folders or app bundles that mean it's installed (home-relative unless absolute).
    public let detect: [String]
    public let format: Format
    /// Reads its config only at launch.
    public let restartNeeded: Bool
    /// CLI name looked up on the login shell's PATH, then in `cliPaths`.
    public let cli: String?
    public let cliPaths: [String]
    let add: [String]?
    let remove: [String]?

    init(id: String, name: String, config: [String], detect: [String], format: Format, restartNeeded: Bool = false,
         cli: String? = nil, cliPaths: [String] = [], add: [String]? = nil, remove: [String]? = nil) {
        self.id = id
        self.name = name
        self.configPaths = config
        self.detect = detect
        self.format = format
        self.restartNeeded = restartNeeded
        self.cli = cli
        self.cliPaths = cliPaths
        self.add = add
        self.remove = remove
    }

    public static let all: [MCPClient] = [
        MCPClient(id: "claude-code", name: "Claude Code", config: [".claude.json"], detect: [".claude", ".claude.json"],
                  format: .json(key: "mcpServers", style: .typed), cli: "claude",
                  add: ["mcp", "add", "--scope", "user", "--transport", "stdio", "gobbl", "--", "{BIN}"],
                  remove: ["mcp", "remove", "gobbl", "--scope", "user"]),
        MCPClient(id: "claude-desktop", name: "Claude", config: ["Library/Application Support/Claude/claude_desktop_config.json"],
                  detect: ["Library/Application Support/Claude", "/Applications/Claude.app"],
                  format: .json(key: "mcpServers", style: .plain), restartNeeded: true),
        MCPClient(id: "codex", name: "Codex and ChatGPT", config: [".codex/config.toml"],
                  detect: [".codex", "/Applications/Codex.app", "/Applications/ChatGPT.app"], format: .codexTOML, cli: "codex",
                  add: ["mcp", "add", "gobbl", "--", "{BIN}"], remove: ["mcp", "remove", "gobbl"]),
        MCPClient(id: "cursor", name: "Cursor", config: [".cursor/mcp.json"], detect: [".cursor", "/Applications/Cursor.app"],
                  format: .json(key: "mcpServers", style: .typed), restartNeeded: true),
        MCPClient(id: "vscode", name: "VS Code", config: ["Library/Application Support/Code/User/mcp.json"],
                  detect: ["Library/Application Support/Code", "/Applications/Visual Studio Code.app"],
                  format: .json(key: "servers", style: .typed), cli: "code",
                  cliPaths: ["/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"],
                  add: ["--add-mcp", #"{"name":"gobbl","command":"{BIN_JSON}","args":[]}"#]),
        MCPClient(id: "windsurf", name: "Windsurf", config: [".codeium/windsurf/mcp_config.json"],
                  detect: [".codeium/windsurf", "/Applications/Windsurf.app"], format: .json(key: "mcpServers", style: .plain),
                  restartNeeded: true),
        MCPClient(id: "gemini", name: "Gemini CLI", config: [".gemini/settings.json"], detect: [".gemini"],
                  format: .json(key: "mcpServers", style: .plain), cli: "gemini",
                  // Gemini defaults to project scope; removal has to name the user scope it was added to.
                  add: ["mcp", "add", "-s", "user", "gobbl", "{BIN}"], remove: ["mcp", "remove", "-s", "user", "gobbl"]),
        MCPClient(id: "lmstudio", name: "LM Studio", config: [".cache/lm-studio/mcp.json", ".lmstudio/mcp.json"],
                  detect: [".lmstudio", ".cache/lm-studio", "/Applications/LM Studio.app"], format: .json(key: "mcpServers", style: .plain)),
        MCPClient(id: "zed", name: "Zed", config: [".config/zed/settings.json"], detect: [".config/zed", "/Applications/Zed.app"],
                  format: .json(key: "context_servers", style: .zed)),
    ]

    private static func resolve(_ path: String, home: URL) -> String {
        path.hasPrefix("/") ? path : home.appendingPathComponent(path).path
    }

    public func isInstalled(home: URL, exists: (String) -> Bool) -> Bool {
        detect.contains { exists(Self.resolve($0, home: home)) }
    }

    public func configURL(home: URL, exists: (String) -> Bool) -> URL {
        let candidates = configPaths.map { home.appendingPathComponent($0) }
        if candidates.count > 1, let found = candidates.first(where: { exists($0.deletingLastPathComponent().path) }) { return found }
        return candidates.last!
    }

    /// CLI arguments that add Gobbl, with `command` filled in.
    public func addArguments(command: String) -> [String]? {
        let json = (try? JSONSerialization.data(withJSONObject: command, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self).dropFirst().dropLast() }.map(String.init) ?? command
        return add?.map { $0.replacingOccurrences(of: "{BIN_JSON}", with: json).replacingOccurrences(of: "{BIN}", with: command) }
    }

    public func removeArguments() -> [String]? { remove }
}
