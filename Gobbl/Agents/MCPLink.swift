import AppKit
import GobblCore
import Observation

/// Points AI apps at Gobbl's MCP server, only when the user asks. Each app's
/// CLI is used when it's on the login shell's PATH; otherwise its config file
/// is edited (first version kept as `<file>.gobbl-backup`). Everything here
/// does file and process I/O, so call it off the main thread.
enum MCPLink {
    static let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Gobbl")
    /// What configs point at: a script that runs gobbl-mcp from the current Gobbl.app.
    static let shimURL = supportDirectory.appendingPathComponent("bin/gobbl-mcp")
    static let requestLogURL = supportDirectory.appendingPathComponent("mcp-requests.jsonl")

    enum Status: Equatable, Sendable {
        case connected
        case notConnected
        /// Gobbl left the file alone; the user adds it by hand.
        case manual(String)
        case failed(String)
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    static func installedClients() -> [MCPClient] {
        MCPClient.all.filter { $0.isInstalled(home: home, exists: exists) }
    }

    static func configURL(_ client: MCPClient) -> URL {
        client.configURL(home: home, exists: exists).resolvingSymlinksInPath()
    }

    // MARK: Shim

    static func installShim() throws {
        let script = MCPShim.script(appPath: Bundle.main.bundlePath)
        try FileManager.default.createDirectory(at: shimURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? String(contentsOf: shimURL, encoding: .utf8)) != script {
            try Data(script.utf8).write(to: shimURL, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
    }

    /// Gobbl.app may have moved since the shim was written.
    static func refreshShimIfInstalled() {
        if exists(shimURL.path) { try? installShim() }
    }

    // MARK: Status

    static func currentCommand(_ client: MCPClient) -> String? {
        let url = configURL(client)
        switch client.format {
        case .json(let key, _):
            return AgentHookConfig.mcpCommand(try? Data(contentsOf: url), key: key)
        case .codexTOML:
            return AgentHookConfig.codexMCPCommand((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        }
    }

    static func status(_ client: MCPClient) -> Status { currentCommand(client) == nil ? .notConnected : .connected }

    // MARK: Connecting

    static func connect(_ client: MCPClient) -> Status {
        do { try installShim() } catch { return .failed("Couldn't install the gobbl-mcp command") }
        let command = shimURL.path
        let current = currentCommand(client)
        if current == command { return .connected }
        if let cli = cliPath(client), let add = client.addArguments(command: command) {
            if current != nil, let remove = client.removeArguments() { _ = run(cli, remove) }
            if run(cli, add).ok, currentCommand(client) == command { return .connected }
        }
        return editFile(client, install: true)
    }

    static func disconnect(_ client: MCPClient) -> Status {
        guard currentCommand(client) != nil else { return .notConnected }
        if let cli = cliPath(client), let remove = client.removeArguments(), run(cli, remove).ok, currentCommand(client) == nil {
            return .notConnected
        }
        return editFile(client, install: false)
    }

    private static func editFile(_ client: MCPClient, install: Bool) -> Status {
        let url = configURL(client)
        let old = try? Data(contentsOf: url)
        do {
            let new: Data
            switch client.format {
            case .json(let key, let style):
                new = install
                    ? try AgentHookConfig.installMCP(into: old, key: key, entry: AgentHookConfig.mcpEntry(style, command: shimURL.path))
                    : try AgentHookConfig.uninstallMCP(from: old, key: key)
            case .codexTOML:
                let text = old.map { String(decoding: $0, as: UTF8.self) } ?? ""
                new = Data((install ? AgentHookConfig.installCodexMCP(into: text, command: shimURL.path)
                                    : AgentHookConfig.uninstallCodexMCP(from: text)).utf8)
            }
            if new != old { try write(new, to: url, old: old) }
            return install ? .connected : .notConnected
        } catch AgentHookConfig.MCPConfigError.jsonc {
            return .manual("Its settings have comments: add Gobbl by hand")
        } catch AgentHookConfig.MCPConfigError.invalidJSON, AgentHookConfig.MCPConfigError.notJSONObject {
            return .manual("Its settings file isn't valid JSON: edit it by hand")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Atomic, keeping the file's permissions and the first backup (the file before Gobbl ever changed it).
    private static func write(_ data: Data, to url: URL, old: Data?) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]
        let backup = url.appendingPathExtension("gobbl-backup")
        if let old, !fm.fileExists(atPath: backup.path) {
            try old.write(to: backup)
            if let permissions { try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: backup.path) }
        }
        try data.write(to: url, options: .atomic)
        if let permissions { try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
    }

    // MARK: CLIs

    private static let pathLock = NSLock()
    private static var cachedPATH: String?

    /// The PATH a Terminal would have (nvm, Homebrew…), which a GUI app doesn't inherit.
    static func loginPATH() -> String {
        pathLock.lock()
        defer { pathLock.unlock() }
        if let cachedPATH { return cachedPATH }
        let fallback = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            + ":/opt/homebrew/bin:/usr/local/bin:\(home.path)/.local/bin"
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let marker = "__GOBBL_PATH__"
        let result = run(shell, ["-ilc", "printf '\\n\(marker)%s\\n' \"$PATH\""], path: fallback, timeout: 6)
        let found = result.output.components(separatedBy: "\n").last { $0.hasPrefix(marker) }.map { String($0.dropFirst(marker.count)) }
        let path = (found?.isEmpty == false ? found! + ":" : "") + fallback
        cachedPATH = path
        return path
    }

    static func cliPath(_ client: MCPClient) -> String? {
        guard let name = client.cli else { return nil }
        for dir in loginPATH().split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return client.cliPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], path: String? = nil, timeout: TimeInterval = 30) -> (ok: Bool, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path ?? loginPATH()
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, "") }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }
}

/// State for the "Memory for AI apps" settings: which apps are here, which
/// are connected, and the one switch that connects them all.
@MainActor @Observable
final class MCPConnector {
    static let shared = MCPConnector()

    struct Row: Identifiable, Sendable {
        let client: MCPClient
        var status: MCPLink.Status
        var id: String { client.id }
    }

    private enum Keys {
        static let auto = "mcpAutoConnect"
        /// Apps already connected once, so launch only picks up newly installed ones.
        static let attempted = "mcpAttemptedClients"
    }

    private(set) var rows: [Row] = []
    private(set) var busy = false
    private(set) var loaded = false
    private(set) var autoConnect = UserDefaults.standard.bool(forKey: Keys.auto)
    private(set) var requestCount = 0
    private(set) var lastRequest: Date?
    /// Apps whose config changed this session and that read it only at launch.
    private(set) var restartNeeded: Set<String> = []

    func refresh() {
        Task.detached(priority: .userInitiated) {
            let rows = MCPLink.installedClients().map { Row(client: $0, status: MCPLink.status($0)) }
            let count = MCPRequestLog.count(at: MCPLink.requestLogURL)
            let last = MCPRequestLog.lastRequest(at: MCPLink.requestLogURL)
            await MainActor.run {
                self.rows = rows
                self.requestCount = count
                self.lastRequest = last
                self.loaded = true
            }
        }
    }

    func setAutoConnect(_ on: Bool) {
        autoConnect = on
        UserDefaults.standard.set(on, forKey: Keys.auto)
        busy = true
        Task.detached(priority: .userInitiated) {
            let clients = MCPLink.installedClients()
            var rows: [Row] = []
            var changed: [String] = []
            for client in clients {
                let before = MCPLink.status(client)
                let after = on ? MCPLink.connect(client) : MCPLink.disconnect(client)
                if before != after, client.restartNeeded { changed.append(client.id) }
                rows.append(Row(client: client, status: after))
            }
            await MainActor.run {
                UserDefaults.standard.set(on ? clients.map(\.id) : [], forKey: Keys.attempted)
                self.rows = rows
                self.restartNeeded.formUnion(changed)
                self.busy = false
            }
        }
    }

    /// At launch: keep the shim pointing at this copy of Gobbl and, if the
    /// switch is on, connect apps installed since last time.
    func launch() {
        let auto = autoConnect
        Task.detached(priority: .utility) {
            MCPLink.refreshShimIfInstalled()
            guard auto else { return }
            let attempted = Set(UserDefaults.standard.stringArray(forKey: Keys.attempted) ?? [])
            let fresh = MCPLink.installedClients().filter { !attempted.contains($0.id) }
            guard !fresh.isEmpty else { return }
            for client in fresh { _ = MCPLink.connect(client) }
            UserDefaults.standard.set(Array(attempted) + fresh.map(\.id), forKey: Keys.attempted)
        }
    }
}
