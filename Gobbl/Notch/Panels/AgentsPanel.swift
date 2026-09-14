import GobblCore
import SwiftUI

/// Claude Code and Codex sessions, and Allow/Deny for permission requests.
struct AgentsPanel: View {
    @State private var hub = AgentHub.shared

    var body: some View {
        if let prompt = hub.pending.first {
            PermissionCard(prompt: prompt, more: hub.pending.count - 1)
        } else if hub.sessions.isEmpty {
            EmptyAgents()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Agents").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("\(hub.sessions.count)").font(.mono(11)).foregroundStyle(Palette.textTertiary)
                    Spacer()
                    if hub.sessions.contains(where: { if case .done = $0.state { true } else { false } }) {
                        PillButton(title: "Clear", symbol: "xmark") { hub.clearFinished() }
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(hub.sessions) { AgentRow(session: $0) }
                    }
                }
            }
        }
    }
}

private struct PermissionCard: View {
    let prompt: AgentHub.PermissionPrompt
    let more: Int
    private var hub: AgentHub { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                AgentIcon(source: prompt.source)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(prompt.source.displayName) wants to use \(prompt.tool)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(prompt.project).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(max(0, Int(prompt.deadline.timeIntervalSince(context.date))))s")
                        .font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
                }
            }
            if let detail = prompt.detail {
                Text(detail)
                    .font(.mono(11))
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.05)))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                PillButton(title: "Allow", symbol: "checkmark", prominent: true) { hub.decide(prompt, allow: true) }
                PillButton(title: "Deny", symbol: "xmark") { hub.decide(prompt, allow: false) }
                PillButton(title: "Ask in terminal", symbol: "terminal") { hub.askInTerminal(prompt) }
                Spacer()
                if more > 0 {
                    Text("+\(more) more").font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.gold.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.gold.opacity(0.35), lineWidth: 1))
    }
}

private struct AgentRow: View {
    let session: AgentSession
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            AgentIcon(source: session.source)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.project).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text(stateText).font(.system(size: 10.5)).foregroundStyle(stateColor).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(session.updated.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                .font(.system(size: 9.5)).foregroundStyle(Palette.textTertiary).fixedSize()
            if session.hostApp != nil {
                IconButton(symbol: "arrow.up.forward.app", help: "Open", size: 10) { AgentHub.shared.open(session) }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Palette.wellHover : Palette.well))
        .onHover { hovering = $0 }
    }

    private var stateText: String {
        switch session.state {
        case .idle: return "Idle"
        case .working(let tool): return tool.map { "Working · \($0)" } ?? "Thinking…"
        case .waiting(let message): return message
        case .done(let message): return "Done" + (message.map { " · " + $0.split(whereSeparator: \.isNewline).joined(separator: " ") } ?? "")
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .working: Palette.accent
        case .waiting: Palette.gold
        default: Palette.textSecondary
        }
    }
}

struct AgentIcon: View {
    let source: AgentEvent.Source

    var body: some View {
        Image(systemName: source == .claude ? "asterisk" : "chevron.left.forwardslash.chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(source == .claude ? Color(hex: 0xE8825B) : Palette.text)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

private struct EmptyAgents: View {
    @State private var claude = AgentLink.claudeStatus().connected
    @State private var codex = AgentLink.codexConnected()

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.accent)
            if claude || codex {
                Text("Gob is watching \([claude ? "Claude Code" : nil, codex ? "Codex" : nil].compactMap { $0 }.joined(separator: " and ")).")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Start a task and Gob works along, then cheers when it's done.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            } else {
                Text("Let Gob cheer on your AI agents").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Connect Claude Code or Codex: Gob works along, cheers when a task finishes, and can approve prompts from the notch.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                PillButton(title: "Connect…", symbol: "link", prominent: true) { AppActions.openSettings() }
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
