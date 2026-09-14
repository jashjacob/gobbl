import Foundation
import GobblCore

// gobbl-mcp: Gobbl's MCP server, which lets AI apps (Claude, Codex, Cursor…)
// read the user's Gobbl memory. JSON-RPC 2.0 over stdio, one message per
// line. Stdout carries only the protocol; logs go to stderr.

signal(SIGPIPE, SIG_IGN)

func log(_ message: String) {
    FileHandle.standardError.write(Data("gobbl-mcp: \(message)\n".utf8))
}

struct Paths {
    var memory: URL
    var socket: String
    var requestLog: URL

    static func resolve() -> Paths {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gobbl")
        var paths = Paths(memory: support.appendingPathComponent("memory.sqlite"),
                          socket: support.appendingPathComponent("agent.sock").path,
                          requestLog: support.appendingPathComponent("mcp-requests.jsonl"))
        #if DEBUG
        // Test hooks, compiled out of release builds.
        let env = ProcessInfo.processInfo.environment
        if let p = env["GOBBL_MEMORY_PATH"] { paths.memory = URL(fileURLWithPath: p) }
        if let p = env["GOBBL_SOCKET_PATH"] { paths.socket = p }
        if let p = env["GOBBL_MCP_LOG_PATH"] { paths.requestLog = URL(fileURLWithPath: p) }
        #endif
        return paths
    }
}

/// Opened on first use, read-only, and retried until Memory is turned on.
final class StoreBox: @unchecked Sendable {
    private let url: URL
    private var store: MemoryStore?

    init(url: URL) { self.url = url }

    func open() -> MemoryStore? {
        if let store { return store }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            store = try MemoryStore(url: url, readOnly: true)
        } catch {
            log("couldn't open memory: \(error)")
        }
        return store
    }
}

let paths = Paths.resolve()
let box = StoreBox(url: paths.memory)
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let tools = MCPTools(openStore: { box.open() }, bridge: { try MCPSocketBridge.send($0, path: paths.socket) })
let server = MCPServer(version: version, tools: tools) { MCPRequestLog.append(tool: $0, to: paths.requestLog) }

let stdout = FileHandle.standardOutput
while let line = readLine(strippingNewline: true) {
    guard let reply = server.handle(line: line) else { continue }
    do {
        try stdout.write(contentsOf: Data((reply + "\n").utf8))
    } catch {
        break  // The client went away.
    }
}
