import AppKit
import GobblCore

/// Connects Claude Code and Codex to Gobbl, only when the user asks:
/// installs the `gobbl-agent` helper and adds (or removes) Gobbl's entries in
/// ~/.claude/settings.json and ~/.codex/config.toml. Each file is backed up to
/// `<file>.gobbl-backup` before it is changed; symlinked dotfiles are followed.
@MainActor
enum AgentLink {
    static let helperURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Gobbl/bin/gobbl-agent")

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
    static var codexConfig: URL { home.appendingPathComponent(".codex/config.toml") }

    static var claudeInstalled: Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path) }
    static var codexInstalled: Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path) }

    // MARK: Claude Code

    static func claudeStatus() -> (connected: Bool, approvals: Bool) {
        AgentHookConfig.claudeStatus(try? Data(contentsOf: claudeSettings))
    }

    static func connectClaude(approvals: Bool) throws {
        try installHelper()
        let url = claudeSettings.resolvingSymlinksInPath()
        let old = try? Data(contentsOf: url)
        let new = try AgentHookConfig.installClaude(into: old, helper: helperURL.path, approvals: approvals)
        try write(new, to: url, backup: old)
        UserDefaults.standard.set(approvals, forKey: "agentApprovals")
    }

    static func disconnectClaude() throws {
        let url = claudeSettings.resolvingSymlinksInPath()
        guard let old = try? Data(contentsOf: url) else { return }
        try write(try AgentHookConfig.uninstallClaude(from: old), to: url, backup: old)
        UserDefaults.standard.set(false, forKey: "agentApprovals")
    }

    // MARK: Codex

    static func codexConnected() -> Bool {
        AgentHookConfig.codexConnected((try? String(contentsOf: codexConfig, encoding: .utf8)) ?? "")
    }

    static func connectCodex() throws {
        try installHelper()
        let url = codexConfig.resolvingSymlinksInPath()
        let old = try? String(contentsOf: url, encoding: .utf8)
        let new = try AgentHookConfig.installCodex(into: old ?? "", helper: helperURL.path)
        try write(Data(new.utf8), to: url, backup: old.map { Data($0.utf8) })
    }

    static func disconnectCodex() throws {
        let url = codexConfig.resolvingSymlinksInPath()
        guard let old = try? String(contentsOf: url, encoding: .utf8) else { return }
        try write(Data(AgentHookConfig.uninstallCodex(from: old).utf8), to: url, backup: Data(old.utf8))
    }

    // MARK: Test

    /// Sends a fake "task done" through the real helper and socket.
    static func sendTest() {
        do { try installHelper() } catch { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [helperURL.path, "codex",
                       #"{"type":"agent-turn-complete","turn-id":"test","last-assistant-message":"Hello from Gobbl","cwd":"/Gobbl test"}"#]
        try? p.run()
    }

    // MARK: Files

    /// Copies the bundled helper to a stable path (the app bundle may move).
    static func installHelper() throws {
        guard let source = Bundle.main.url(forResource: "gobbl-agent", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: helperURL.path) { try fm.removeItem(at: helperURL) }
        try fm.copyItem(at: source, to: helperURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
    }

    private static func write(_ data: Data, to url: URL, backup: Data?) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the first backup: the file as it was before Gobbl ever changed it.
        let backupURL = url.appendingPathExtension("gobbl-backup")
        if let backup, !FileManager.default.fileExists(atPath: backupURL.path) { try backup.write(to: backupURL) }
        try data.write(to: url, options: .atomic)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case AgentHookConfig.ConfigError.notJSONObject:
            return "~/.claude/settings.json isn't a JSON object, so Gobbl left it alone."
        case AgentHookConfig.ConfigError.existingNotify(let line):
            return "Codex already has a notify command (\(line)). Codex allows only one, so Gobbl left it alone."
        default:
            return error.localizedDescription
        }
    }
}
