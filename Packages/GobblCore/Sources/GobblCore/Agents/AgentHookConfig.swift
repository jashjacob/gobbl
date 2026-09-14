import Foundation

/// Adds and removes Gobbl's entries in Claude Code's settings.json and Codex's
/// config.toml without disturbing anything else in those files. Pure
/// functions over the file contents so they can be tested; the app does the I/O.
public enum AgentHookConfig {
    /// Every command Gobbl installs contains this, which is how we find our own entries.
    public static let marker = "gobbl-agent"

    /// Hook events Gobbl listens to. All run async (Claude never waits on
    /// Gobbl) except PermissionRequest, which exists to wait for an answer.
    public static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"]

    public static func claudeCommand(helper: String) -> String {
        "/usr/bin/perl \"\(helper)\" claude"
    }

    public enum ConfigError: Error, Equatable {
        case notJSONObject
        case existingNotify(String)
    }

    // MARK: Claude Code

    /// Returns settings.json contents with Gobbl's hooks installed (replacing any previous Gobbl entries).
    public static func installClaude(into data: Data?, helper: String, approvals: Bool, approvalTimeout: Int = 45) throws -> Data {
        var root = try parse(data)
        var hooks = strip(root["hooks"] as? [String: Any] ?? [:])
        let command = claudeCommand(helper: helper)
        for event in claudeEvents {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "async": true]]])
            hooks[event] = groups
        }
        if approvals {
            var groups = hooks["PermissionRequest"] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "timeout": approvalTimeout]]])
            hooks["PermissionRequest"] = groups
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    /// Returns settings.json contents with every Gobbl hook removed.
    public static func uninstallClaude(from data: Data?) throws -> Data {
        var root = try parse(data)
        let hooks = strip(root["hooks"] as? [String: Any] ?? [:])
        if hooks.isEmpty { root["hooks"] = nil } else { root["hooks"] = hooks }
        return try serialize(root)
    }

    public static func claudeStatus(_ data: Data?) -> (connected: Bool, approvals: Bool) {
        guard let root = try? parse(data), let hooks = root["hooks"] as? [String: Any] else { return (false, false) }
        func has(_ event: String) -> Bool {
            (hooks[event] as? [[String: Any]] ?? []).contains(where: isOurs)
        }
        return (claudeEvents.contains(where: has), has("PermissionRequest"))
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) ?? false }
    }

    /// Removes Gobbl's hook groups, and events left empty by that.
    private static func strip(_ hooks: [String: Any]) -> [String: Any] {
        var out = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurs($0) }
            out[event] = kept.isEmpty ? nil : kept
        }
        return out
    }

    private static func parse(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty,
              !(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ConfigError.notJSONObject }
        return root
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    // MARK: Codex

    public static func codexLine(helper: String) -> String {
        "notify = [\"/usr/bin/perl\", \"\(helper)\", \"codex\"] # added by Gobbl"
    }

    /// Returns config.toml with Gobbl's notify line. Refuses to replace a notify someone else set.
    public static func installCodex(into text: String, helper: String) throws -> String {
        let lines = uninstallCodex(from: text).components(separatedBy: "\n")
        // Only top-level keys (before the first [table]) matter for notify.
        let topLevel = lines.prefix { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }
        if let existing = topLevel.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }) {
            throw ConfigError.existingNotify(existing.trimmingCharacters(in: .whitespaces))
        }
        // A top-level key must come before any table, so it goes first.
        let body = lines.joined(separator: "\n")
        return codexLine(helper: helper) + "\n" + body
    }

    public static func uninstallCodex(from text: String) -> String {
        text.components(separatedBy: "\n").filter { !$0.contains(marker) }.joined(separator: "\n")
    }

    public static func codexConnected(_ text: String) -> Bool { text.contains(marker) }
}
