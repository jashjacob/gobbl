import Foundation

/// One message from an AI coding agent, decoded from a Claude Code hook
/// payload (stdin JSON) or a Codex `notify` payload (argv JSON).
public struct AgentEvent: Equatable, Sendable {
    public enum Source: String, Sendable, CaseIterable {
        case claude, codex

        public var displayName: String { self == .claude ? "Claude Code" : "Codex" }
    }

    public enum Kind: Equatable, Sendable {
        case sessionStart
        case promptSubmitted
        case toolUse(String)
        /// Claude wants to use a tool; with approvals on, Gobbl can answer.
        case permissionRequest(tool: String, detail: String?)
        /// A "needs you" notification: a permission prompt or a question.
        case needsInput(String)
        case turnDone(String?)
        case sessionEnd
    }

    public var source: Source
    public var sessionID: String
    public var cwd: String?
    public var kind: Kind

    public init(source: Source, sessionID: String, cwd: String?, kind: Kind) {
        self.source = source
        self.sessionID = sessionID
        self.cwd = cwd
        self.kind = kind
    }

    /// Returns nil for events Gob doesn't care about.
    public static func parse(source: Source, json: Data) -> AgentEvent? {
        guard let o = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        func str(_ key: String) -> String? { (o[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let cwd = str("cwd")

        switch source {
        case .codex:
            // notify payload: {"type":"agent-turn-complete","turn-id":…,"last-assistant-message":…,"cwd"?}
            guard str("type") == "agent-turn-complete" else { return nil }
            return AgentEvent(source: .codex, sessionID: "codex:\(cwd ?? "default")", cwd: cwd,
                              kind: .turnDone(str("last-assistant-message")))
        case .claude:
            guard let event = str("hook_event_name") else { return nil }
            let session = str("session_id") ?? "claude"
            let kind: Kind
            switch event {
            case "SessionStart": kind = .sessionStart
            case "UserPromptSubmit": kind = .promptSubmitted
            case "PreToolUse", "PostToolUse": kind = .toolUse(str("tool_name") ?? "tool")
            case "PermissionRequest":
                kind = .permissionRequest(tool: str("tool_name") ?? "a tool", detail: Self.detail(o["tool_input"]))
            case "Notification":
                switch str("notification_type") {
                case "permission_prompt": kind = .needsInput("Needs your permission")
                case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input": kind = .needsInput("Has a question")
                default: return nil // idle_prompt fires after a finished turn: nothing new to say
                }
            case "Stop": kind = .turnDone(str("last_assistant_message"))
            case "SessionEnd": kind = .sessionEnd
            default: return nil
            }
            return AgentEvent(source: .claude, sessionID: session, cwd: cwd, kind: kind)
        }
    }

    /// The interesting part of a tool call: a command, a path, a URL.
    static func detail(_ input: Any?) -> String? {
        guard let input = input as? [String: Any] else { return nil }
        for key in ["command", "file_path", "path", "url", "pattern", "description", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty { return String(value.prefix(300)) }
        }
        return nil
    }
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case working(tool: String?)
        case waiting(String)
        case done(String?)
    }

    public var id: String
    public var source: AgentEvent.Source
    public var cwd: String?
    public var state: State
    public var updated: Date
    public var started: Date
    /// Bundle ID of the app the prompt was typed in (the terminal or editor), to jump back to.
    public var hostApp: String?

    public var project: String {
        guard let cwd else { return source.displayName }
        return (cwd as NSString).lastPathComponent
    }

    public var isWorking: Bool {
        if case .working = state { return true }
        return false
    }
}

/// All live agent sessions, newest activity first.
public struct AgentTracker: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        case none
        case startedWorking
        case needsYou(String)
        case done(String?)
    }

    public static let staleWorking: TimeInterval = 10 * 60
    public static let forgetDone: TimeInterval = 20 * 60

    public private(set) var sessions: [AgentSession] = []

    public init() {}

    public var anyWorking: Bool { sessions.contains(where: \.isWorking) }

    @discardableResult
    public mutating func apply(_ e: AgentEvent, now: Date = Date(), hostApp: String? = nil) -> Effect {
        if e.kind == .sessionEnd {
            sessions.removeAll { $0.id == e.sessionID }
            return .none
        }
        var s = sessions.first { $0.id == e.sessionID }
            ?? AgentSession(id: e.sessionID, source: e.source, cwd: e.cwd, state: .idle, updated: now, started: now)
        sessions.removeAll { $0.id == e.sessionID }
        let wasWorking = s.isWorking
        s.updated = now
        if let cwd = e.cwd { s.cwd = cwd }
        var effect = Effect.none
        switch e.kind {
        case .sessionStart:
            s.state = .idle
        case .promptSubmitted:
            s.state = .working(tool: nil)
            if let hostApp { s.hostApp = hostApp }
            effect = wasWorking ? .none : .startedWorking
        case .toolUse(let tool):
            s.state = .working(tool: tool)
            effect = wasWorking ? .none : .startedWorking
        case .permissionRequest(let tool, _):
            s.state = .waiting("Wants to use \(tool)")
            effect = .needsYou("Wants to use \(tool)")
        case .needsInput(let message):
            // A permission request already said this more precisely.
            if case .waiting = s.state { break }
            s.state = .waiting(message)
            effect = .needsYou(message)
        case .turnDone(let message):
            s.state = .done(message)
            effect = .done(message)
        case .sessionEnd:
            break
        }
        sessions.insert(s, at: 0)
        return effect
    }

    /// After a decision from the notch, the agent carries on.
    public mutating func resolveWaiting(_ sessionID: String, now: Date = Date()) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }), case .waiting = sessions[i].state else { return }
        sessions[i].state = .working(tool: nil)
        sessions[i].updated = now
    }

    /// Working sessions with no news for 10 minutes go idle (a crash or a
    /// closed terminal sends nothing); finished ones are forgotten after 20.
    public mutating func expire(now: Date = Date()) {
        for i in sessions.indices where sessions[i].isWorking && now.timeIntervalSince(sessions[i].updated) > Self.staleWorking {
            sessions[i].state = .idle
        }
        sessions.removeAll { s in
            switch s.state {
            case .done, .idle: return now.timeIntervalSince(s.updated) > Self.forgetDone
            default: return false
            }
        }
    }
}
