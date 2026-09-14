import Foundation
import Testing
@testable import GobblCore

@Suite struct MCPConfigTests {
    private let bin = "/Users/me/Library/Application Support/Gobbl/bin/gobbl-mcp"

    private func json(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }
    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func orderedJSONRoundTrips() throws {
        let source = "{\n  \"z\": 1.50,\n  \"a\": {\n    \"x\": [\n      true,\n      \"caf\\u00e9 \\/ \\\"q\\\"\"\n    ]\n  },\n  \"e\": [],\n  \"o\": {}\n}"
        #expect(try OrderedJSON.parse(source).serialized() == source)
        #expect(OrderedJSON.detectIndent("{\n    \"a\": 1\n}") == "    ")
        #expect(try OrderedJSON.parse(#"{"a":"x"}"#)["a"]?.stringValue == "x")
    }

    @Test func installKeepsEverythingElseInOrder() throws {
        let existing = "{\n  \"numStartups\": 5,\n  \"mcpServers\": {\n    \"other\": {\n      \"command\": \"x\"\n    }\n  },\n  \"zeta\": true\n}\n"
        let entry = AgentHookConfig.mcpEntry(.typed, command: bin)
        let once = try AgentHookConfig.installMCP(into: Data(existing.utf8), key: "mcpServers", entry: entry)
        #expect(text(once) == "{\n  \"numStartups\": 5,\n  \"mcpServers\": {\n    \"other\": {\n      \"command\": \"x\"\n    },\n    \"gobbl\": {\n      \"type\": \"stdio\",\n      \"command\": \"\(bin)\",\n      \"args\": []\n    }\n  },\n  \"zeta\": true\n}\n")
        #expect(AgentHookConfig.mcpCommand(once, key: "mcpServers") == bin)
        #expect(try AgentHookConfig.installMCP(into: once, key: "mcpServers", entry: entry) == once)
        let removed = try AgentHookConfig.uninstallMCP(from: once, key: "mcpServers")
        #expect(text(removed) == existing)
        #expect(AgentHookConfig.mcpCommand(removed, key: "mcpServers") == nil)
    }

    @Test func findsOurEntryUnderAnotherName() throws {
        let existing = #"{"mcpServers":{"memory":{"command":"/old/bin/gobbl-mcp"},"keep":{"command":"npx"}}}"#
        #expect(AgentHookConfig.mcpCommand(Data(existing.utf8), key: "mcpServers") == "/old/bin/gobbl-mcp")
        let out = try AgentHookConfig.installMCP(into: Data(existing.utf8), key: "mcpServers", entry: AgentHookConfig.mcpEntry(.plain, command: bin))
        let servers = json(out)["mcpServers"] as? [String: Any]
        #expect(Set(servers?.keys.map { $0 } ?? []) == ["keep", "gobbl"])
    }

    @Test func createsTheFileAndOtherShapes() throws {
        let vscode = try AgentHookConfig.installMCP(into: nil, key: "servers", entry: AgentHookConfig.mcpEntry(.typed, command: bin))
        #expect((json(vscode)["servers"] as? [String: [String: Any]])?["gobbl"]?["type"] as? String == "stdio")
        let zed = try AgentHookConfig.installMCP(into: Data("{\n\t\"theme\": \"One\"\n}".utf8), key: "context_servers",
                                                 entry: AgentHookConfig.mcpEntry(.zed, command: bin))
        #expect(text(zed).hasPrefix("{\n\t\"theme\": \"One\",\n\t\"context_servers\": {\n\t\t\"gobbl\": {"))
        #expect((json(zed)["context_servers"] as? [String: [String: Any]])?["gobbl"]?["env"] != nil)
    }

    @Test func leavesJSONCAndBrokenFilesAlone() {
        let entry = AgentHookConfig.mcpEntry(.plain, command: bin)
        #expect(throws: AgentHookConfig.MCPConfigError.jsonc) {
            try AgentHookConfig.installMCP(into: Data("{\n  // mine\n  \"servers\": {}\n}".utf8), key: "servers", entry: entry)
        }
        #expect(throws: AgentHookConfig.MCPConfigError.jsonc) {
            try AgentHookConfig.installMCP(into: Data(#"{"servers": {"a": 1,},}"#.utf8), key: "servers", entry: entry)
        }
        #expect(throws: AgentHookConfig.MCPConfigError.invalidJSON) {
            try AgentHookConfig.installMCP(into: Data(#"{"servers": "#.utf8), key: "servers", entry: entry)
        }
        #expect(throws: AgentHookConfig.MCPConfigError.notJSONObject) {
            try AgentHookConfig.installMCP(into: Data("[]".utf8), key: "servers", entry: entry)
        }
        // Status still reads JSONC.
        #expect(AgentHookConfig.mcpCommand(Data("{\n  // x\n  \"servers\": {\"gobbl\": {\"command\": \"a\"},},\n}".utf8), key: "servers") == "a")
    }

    @Test func codexTOML() {
        let existing = "model = \"o3\"\n\n[mcp_servers.other]\ncommand = \"x\"\n"
        let once = AgentHookConfig.installCodexMCP(into: existing, command: bin)
        #expect(once == existing + "\n# added by Gobbl\n[mcp_servers.gobbl]\ncommand = \"\(bin)\"\nargs = []\n")
        #expect(AgentHookConfig.codexMCPCommand(once) == bin)
        #expect(AgentHookConfig.installCodexMCP(into: once, command: bin) == once)
        #expect(AgentHookConfig.uninstallCodexMCP(from: once) == existing)
        #expect(AgentHookConfig.codexMCPCommand(existing) == nil)
        // Added by `codex mcp add`, in the middle, with an env table.
        let middle = "[mcp_servers.gobbl]\ncommand = \"/a/gobbl-mcp\"\n\n[mcp_servers.gobbl.env]\nX = \"1\"\n\n[profiles.fast]\nmodel = \"m\"\n"
        #expect(AgentHookConfig.uninstallCodexMCP(from: middle) == "[profiles.fast]\nmodel = \"m\"\n")
        // A multi-line array isn't a table header.
        let arrays = "args = [\n  [\"a\"],\n]\n"
        #expect(AgentHookConfig.installCodexMCP(into: arrays, command: bin).hasPrefix(arrays))
        #expect(AgentHookConfig.installCodexMCP(into: "", command: bin) == AgentHookConfig.codexMCPBlock(command: bin))
    }

    @Test func clientCatalog() {
        let home = URL(fileURLWithPath: "/Users/me")
        let lm = MCPClient.all.first { $0.id == "lmstudio" }!
        #expect(lm.configURL(home: home, exists: { $0 == "/Users/me/.cache/lm-studio" }).path == "/Users/me/.cache/lm-studio/mcp.json")
        #expect(lm.configURL(home: home, exists: { _ in false }).path == "/Users/me/.lmstudio/mcp.json")
        let cursor = MCPClient.all.first { $0.id == "cursor" }!
        #expect(cursor.isInstalled(home: home, exists: { $0 == "/Applications/Cursor.app" }))
        #expect(!cursor.isInstalled(home: home, exists: { _ in false }))
        let claude = MCPClient.all.first { $0.id == "claude-code" }!
        #expect(claude.addArguments(command: bin)?.last == bin)
        let vscode = MCPClient.all.first { $0.id == "vscode" }!
        #expect(vscode.addArguments(command: bin) == ["--add-mcp", #"{"name":"gobbl","command":"\#(bin)","args":[]}"#])
        #expect(vscode.removeArguments() == nil)
        #expect(Set(MCPClient.all.map(\.id)).count == MCPClient.all.count)
    }

    @Test func requestLogAndShim() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UUID().uuidString).jsonl")
        #expect(MCPRequestLog.count(at: url) == 0)
        MCPRequestLog.append(tool: "search_memory", to: url)
        MCPRequestLog.append(tool: "get_day", at: Date(timeIntervalSince1970: 1_800_000_000), to: url)
        #expect(MCPRequestLog.count(at: url) == 2)
        #expect(MCPRequestLog.lastRequest(at: url) == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try String(contentsOf: url, encoding: .utf8).contains(#"{"at":"#))

        let script = MCPShim.script(appPath: "/Applications/Gob's.app")
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("APP='/Applications/Gob'\\''s.app'"))
        #expect(script.contains(#"exec "$APP/Contents/MacOS/gobbl-mcp" "$@""#))
    }
}
