import SwiftUI

/// Connect / disconnect Claude Code and Codex. Nothing is changed in their
/// config files until the user flips a switch here (or in onboarding).
struct AgentsSettingsSection: View {
    @State private var claude = AgentLink.claudeStatus()
    @State private var codex = AgentLink.codexConnected()
    @State private var error: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { claude.connected }, set: { setClaude($0, approvals: claude.approvals) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code")
                    Text(AgentLink.claudeInstalled ? "Adds Gobbl hooks to ~/.claude/settings.json" : "Claude Code isn't set up on this Mac yet")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if claude.connected {
                Toggle(isOn: Binding(get: { claude.approvals }, set: { setClaude(true, approvals: $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Approve permission prompts from the notch")
                        Text("Allow or Deny without switching to the terminal. Unanswered after 30 s, Claude asks in the terminal as usual.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Toggle(isOn: Binding(get: { codex }, set: setCodex)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex")
                    Text(AgentLink.codexInstalled ? "Sets notify in ~/.codex/config.toml" : "Codex isn't set up on this Mac yet")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
            }
            if claude.connected || codex {
                Button("Send a Test Event") { AgentLink.sendTest() }
            }
        } header: {
            Text("AI Agents")
        } footer: {
            Text("Gob works along while your agent runs and cheers when it finishes. Events go to Gobbl through a private socket on this Mac; nothing is sent anywhere. Each file is backed up to .gobbl-backup before it's changed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func setClaude(_ on: Bool, approvals: Bool) {
        do {
            if on { try AgentLink.connectClaude(approvals: approvals) } else { try AgentLink.disconnectClaude() }
            error = nil
        } catch {
            self.error = AgentLink.describe(error)
        }
        claude = AgentLink.claudeStatus()
    }

    private func setCodex(_ on: Bool) {
        do {
            if on { try AgentLink.connectCodex() } else { try AgentLink.disconnectCodex() }
            error = nil
        } catch {
            self.error = AgentLink.describe(error)
        }
        codex = AgentLink.codexConnected()
    }
}
