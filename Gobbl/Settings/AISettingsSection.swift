import SwiftUI

/// Settings → AI (beta): turn it on, the Gobbl key, today's allowance, and
/// the local log of everything sent.
struct AISettingsSection: View {
    @State private var ai = AIClient.shared
    @AppStorage("gobblKeyEnabled") private var keyEnabled = true
    @State private var verifying = false
    @State private var trusted = MediaKeyTap.isTrusted

    var body: some View {
        Section {
            if ai.isRegistered {
                LabeledContent("Status", value: ai.remainingToday.map { "On · \($0) actions left today" } ?? "On")
            } else {
                HStack {
                    Text("Write, rewrite and polish text anywhere. Free during the beta.")
                    Spacer()
                    Button("Turn On…") { verifying = true }
                }
            }
            if let error = ai.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Toggle(isOn: $keyEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gobbl key: right ⌥")
                    Text("Tap to write or rewrite in any text field. Double-tap for edit mode, hold to dictate. ⌃⌥G also writes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: keyEnabled) { _, on in
                if on && !MediaKeyTap.isTrusted { MediaKeyTap.requestTrust() }
                GobblKey.shared.apply()
            }
            if keyEnabled && !trusted {
                Label("The Gobbl key needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.caption)
            }
            HStack {
                Button("Show What Was Sent") { NSWorkspace.shared.activateFileViewerSelecting([AIClient.logURL]) }
                    .disabled(!FileManager.default.fileExists(atPath: AIClient.logURL.path))
                Spacer()
                if ai.isRegistered {
                    Button("Turn Off", role: .destructive) { ai.signOut() }
                }
            }
        } header: {
            Text("AI (beta)")
        } footer: {
            Text("Text you ask Gobbl to write or rewrite, plus the nearby text for context, goes to Xeve's AI service and an AI provider that doesn't keep it. Every request is logged on this Mac so you can check.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $verifying) {
            VerifySheet { _ in verifying = false }
        }
        .task { await ai.refreshQuota() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in trusted = MediaKeyTap.isTrusted }
    }
}
