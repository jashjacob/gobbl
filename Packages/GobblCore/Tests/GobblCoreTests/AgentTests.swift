import Foundation
import Testing
@testable import GobblCore

@Suite struct AgentEventTests {
    private func claude(_ json: String) -> AgentEvent? { AgentEvent.parse(source: .claude, json: Data(json.utf8)) }

    @Test func parsesClaudeLifecycle() {
        #expect(claude(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/src/gobbl"}"#)?.kind == .promptSubmitted)
        #expect(claude(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash"}"#)?.kind == .toolUse("Bash"))
        #expect(claude(#"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"Bash"}"#)?.kind == .toolFinished)
        #expect(claude(#"{"hook_event_name":"Stop","session_id":"s1","last_assistant_message":"All done"}"#)?.kind == .turnDone("All done"))
        #expect(claude(#"{"hook_event_name":"SessionEnd","session_id":"s1"}"#)?.kind == .sessionEnd)
        #expect(claude(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/src/gobbl"}"#)?.cwd == "/src/gobbl")
    }

    @Test func parsesPermissionRequestDetail() {
        let e = claude(#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}"#)
        #expect(e?.kind == .permissionRequest(tool: "Bash", detail: "rm -rf build"))
    }

    @Test func notificationsThatNeedYou() {
        #expect(claude(#"{"hook_event_name":"Notification","session_id":"s","notification_type":"permission_prompt"}"#)?.kind
                == .needsInput("Needs your permission"))
        #expect(claude(#"{"hook_event_name":"Notification","session_id":"s","notification_type":"idle_prompt"}"#) == nil)
    }

    @Test func parsesCodexNotify() {
        let e = AgentEvent.parse(source: .codex, json: Data(#"{"type":"agent-turn-complete","turn-id":"t","last-assistant-message":"Tests pass","cwd":"/src/x"}"#.utf8))
        #expect(e?.kind == .turnDone("Tests pass"))
        #expect(e?.sessionID == "codex:/src/x")
        #expect(AgentEvent.parse(source: .codex, json: Data(#"{"type":"something-else"}"#.utf8)) == nil)
    }

    @Test func ignoresGarbage() {
        #expect(claude("nope") == nil)
        #expect(claude(#"{"hook_event_name":"PreCompact","session_id":"s"}"#) == nil)
    }
}

@Suite struct AgentTrackerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 5_000)

    private func ev(_ kind: AgentEvent.Kind, _ id: String = "s1") -> AgentEvent {
        AgentEvent(source: .claude, sessionID: id, cwd: "/src/gobbl", kind: kind)
    }

    @Test func workThenDone() {
        var t = AgentTracker()
        #expect(t.apply(ev(.promptSubmitted), now: t0, hostApp: "com.mitchellh.ghostty") == .startedWorking)
        #expect(t.apply(ev(.toolUse("Edit")), now: t0) == .none)
        #expect(t.anyWorking)
        #expect(t.sessions[0].project == "gobbl")
        #expect(t.sessions[0].hostApp == "com.mitchellh.ghostty")
        #expect(t.apply(ev(.turnDone("ok")), now: t0) == .done("ok"))
        #expect(!t.anyWorking)
    }

    @Test func thinkingVersusCoding() {
        var t = AgentTracker()
        #expect(t.activity == .idle)
        t.apply(ev(.promptSubmitted), now: t0)
        #expect(t.activity == .thinking)
        t.apply(ev(.toolUse("Edit")), now: t0)
        #expect(t.activity == .coding)
        t.apply(ev(.toolFinished), now: t0)
        #expect(t.activity == .thinking)
        t.apply(ev(.promptSubmitted, "s2"), now: t0)
        t.apply(ev(.toolUse("Bash"), "s2"), now: t0)
        #expect(t.activity == .coding) // any session coding wins
        t.apply(ev(.turnDone(nil)), now: t0)
        t.apply(ev(.turnDone(nil), "s2"), now: t0)
        #expect(t.activity == .idle)
    }

    @Test func permissionThenResolve() {
        var t = AgentTracker()
        t.apply(ev(.promptSubmitted), now: t0)
        #expect(t.apply(ev(.permissionRequest(tool: "Bash", detail: "ls")), now: t0) == .needsYou("Wants to use Bash"))
        // The generic notification for the same prompt adds nothing.
        #expect(t.apply(ev(.needsInput("Needs your permission")), now: t0) == .none)
        t.resolveWaiting("s1", now: t0)
        #expect(t.anyWorking)
    }

    @Test func sessionsExpire() {
        var t = AgentTracker()
        t.apply(ev(.promptSubmitted, "a"), now: t0)
        t.apply(ev(.turnDone(nil), "b"), now: t0)
        t.expire(now: t0.addingTimeInterval(AgentTracker.staleWorking + 1))
        #expect(!t.anyWorking)
        #expect(t.sessions.count == 2)
        t.expire(now: t0.addingTimeInterval(AgentTracker.forgetDone + 1))
        #expect(t.sessions.isEmpty)
    }

    @Test func sessionEndRemoves() {
        var t = AgentTracker()
        t.apply(ev(.promptSubmitted), now: t0)
        t.apply(ev(.sessionEnd), now: t0)
        #expect(t.sessions.isEmpty)
    }
}

@Suite struct AgentHookConfigTests {
    let helper = "/Users/me/Library/Application Support/Gobbl/bin/gobbl-agent"

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func installsAlongsideExistingHooksAndSettings() throws {
        let existing = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        let out = try AgentHookConfig.installClaude(into: Data(existing.utf8), helper: helper, approvals: false)
        let root = try object(out)
        #expect(root["model"] as? String == "opus")
        let hooks = try #require(root["hooks"] as? [String: Any])
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stop.count == 2) // theirs + ours
        #expect(hooks["PermissionRequest"] == nil)
        #expect(AgentHookConfig.claudeStatus(out) == (true, false))
    }

    @Test func reinstallIsIdempotentAndApprovalsToggle() throws {
        let once = try AgentHookConfig.installClaude(into: nil, helper: helper, approvals: true)
        let twice = try AgentHookConfig.installClaude(into: once, helper: helper, approvals: true)
        let hooks = try #require(try object(twice)["hooks"] as? [String: Any])
        #expect((hooks["Stop"] as? [[String: Any]])?.count == 1)
        #expect(AgentHookConfig.claudeStatus(twice) == (true, true))
        let off = try AgentHookConfig.installClaude(into: twice, helper: helper, approvals: false)
        #expect(AgentHookConfig.claudeStatus(off) == (true, false))
    }

    @Test func uninstallLeavesOnlyTheirs() throws {
        let existing = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        let installed = try AgentHookConfig.installClaude(into: Data(existing.utf8), helper: helper, approvals: true)
        let removed = try AgentHookConfig.uninstallClaude(from: installed)
        let hooks = try #require(try object(removed)["hooks"] as? [String: Any])
        #expect(Array(hooks.keys) == ["Stop"])
        #expect(AgentHookConfig.claudeStatus(removed) == (false, false))
    }

    @Test func refusesToClobberInvalidJSON() {
        #expect(throws: AgentHookConfig.ConfigError.notJSONObject) {
            try AgentHookConfig.installClaude(into: Data("[1,2]".utf8), helper: helper, approvals: false)
        }
    }

    @Test func codexNotify() throws {
        let config = "model = \"gpt-5\"\n\n[profiles.fast]\nmodel = \"mini\"\n"
        let installed = try AgentHookConfig.installCodex(into: config, helper: helper)
        #expect(installed.hasPrefix("notify = [\"/usr/bin/perl\""))
        #expect(installed.contains("[profiles.fast]"))
        #expect(AgentHookConfig.codexConnected(installed))
        #expect(AgentHookConfig.uninstallCodex(from: installed) == config)
        #expect(try AgentHookConfig.installCodex(into: installed, helper: helper) == installed)
    }

    @Test func codexRefusesSomeoneElsesNotify() {
        #expect(throws: AgentHookConfig.ConfigError.existingNotify("notify = [\"terminal-notifier\"]")) {
            try AgentHookConfig.installCodex(into: "notify = [\"terminal-notifier\"]\n", helper: helper)
        }
    }
}
