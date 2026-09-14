import GobblCore
import SwiftUI

/// Settings → Memory: the switch, pause, what's kept, which apps and sites, and forgetting.
struct MemorySettingsSection: View {
    @State private var memory = MemoryModel.shared
    @State private var on = MemoryModel.shared.enabled
    @AppStorage(MemoryModel.Keys.retentionDays) private var retention = 0
    @AppStorage(MemoryModel.Keys.quietLargeGroups) private var quietGroups = true
    @AppStorage("todoSensitivity") private var sensitivity = TodoSensitivity.balanced.rawValue
    @AppStorage("memoryMyNames") private var myNames = ""
    @State private var sites = (UserDefaults.standard.stringArray(forKey: MemoryModel.Keys.excludedDomains) ?? []).joined(separator: ", ")
    @State private var confirmForgetAll = false
    @State private var fileVaultOff = false

    var body: some View {
        Section {
            Toggle(isOn: $on) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember what's on screen")
                    Text("Reads the text in the apps you use, never screenshots, and keeps it on this Mac. It powers to-dos, people and search.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: on) { _, value in memory.setEnabled(value) }

            if on {
                HStack {
                    if memory.isPaused, let until = memory.pausedUntil {
                        Label("Paused until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "pause.circle")
                        Spacer()
                        Button("Resume") { memory.resume() }
                    } else {
                        Label(memory.isCapturing ? "Remembering" : "Waiting for Accessibility permission",
                              systemImage: memory.isCapturing ? "circle.fill" : "exclamationmark.triangle")
                            .foregroundStyle(memory.isCapturing ? .green : .orange)
                        Spacer()
                        Menu("Pause") {
                            Button("For 15 minutes") { memory.pause(for: 15 * 60) }
                            Button("For an hour") { memory.pause(for: 3600) }
                            Button("Until tomorrow") { memory.pause(for: nil) }
                        }
                        .fixedSize()
                    }
                }
                if let stats = memory.stats {
                    LabeledContent("Stored", value: "\(stats.chunks.formatted()) snippets · \(ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file))")
                }
                Picker("Keep raw text", selection: $retention) {
                    Text("Forever").tag(0)
                    Text("90 days").tag(90)
                    Text("30 days").tag(30)
                    Text("7 days").tag(7)
                }
                .onChange(of: retention) { _, _ in memory.applyRetention(); memory.refreshStats() }
                Picker("To-do suggestions", selection: $sensitivity) {
                    Text("Fewer, surer").tag(TodoSensitivity.conservative.rawValue)
                    Text("Balanced").tag(TodoSensitivity.balanced.rawValue)
                    Text("More").tag(TodoSensitivity.eager.rawValue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Your name in chats", text: $myNames, prompt: Text(NSFullUserName()))
                        .onSubmit { memory.pushSettings() }
                    Text("How you appear in WhatsApp, Slack and Teams, so Gobbl knows which messages are yours. Separate more than one with commas. Gobbl also learns it on its own.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("In busy group chats, keep only my messages and mentions", isOn: $quietGroups)
                    .onChange(of: quietGroups) { _, _ in memory.pushSettings() }

                DisclosureGroup("Apps") {
                    if memory.seenApps.isEmpty {
                        Text("Apps appear here as you use them.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(memory.seenApps.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }, id: \.key) { bundle, name in
                        Toggle(name, isOn: Binding(get: { memory.isAllowed(bundle) }, set: { memory.setApp(bundle, allowed: $0) }))
                    }
                    Text("Password managers, Keychain, System Settings and private browser windows are never read. Code editors and terminals are off unless you turn them on.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Sites to skip, separated by commas", text: $sites)
                        .onSubmit(saveSites)
                    Text("Banking, brokerage and health sites are skipped already.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Memory…") { MemoryWindow.show() }
                    Menu("Forget…") {
                        Button("The last 15 minutes") { memory.forget(last: 15 * 60) }
                        Button("Today") { memory.forget(last: Date().timeIntervalSince(Calendar.current.startOfDay(for: Date()))) }
                        Divider()
                        Button("Everything…", role: .destructive) { confirmForgetAll = true }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Show What Was Sent to the AI") { NSWorkspace.shared.activateFileViewerSelecting([AIClient.logURL]) }
                        .disabled(!FileManager.default.fileExists(atPath: AIClient.logURL.path))
                }
                if fileVaultOff {
                    Label("FileVault is off, so memory isn't encrypted on disk. Turn it on in System Settings → Privacy & Security.",
                          systemImage: "lock.open").font(.caption).foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Memory (beta)")
        } footer: {
            Text("Everything stays on this Mac. Only short batches of relevant text, with secrets masked, are sent to Gobbl's AI to find to-dos and people.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Forget everything Gobbl remembers?", isPresented: $confirmForgetAll) {
            Button("Forget Everything", role: .destructive) { memory.forget(last: nil) }
        } message: {
            Text("This can't be undone.")
        }
        .task {
            memory.refreshStats()
            fileVaultOff = await Self.fileVaultIsOff()
        }
    }

    private func saveSites() {
        let list = sites.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        UserDefaults.standard.set(list, forKey: MemoryModel.Keys.excludedDomains)
        memory.pushSettings()
    }

    private static func fileVaultIsOff() async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
            process.arguments = ["status"]
            let pipe = Pipe()
            process.standardOutput = pipe
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return out.contains("FileVault is Off")
        }.value
    }
}
