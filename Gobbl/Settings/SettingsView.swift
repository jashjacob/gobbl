import GobblCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var pet = PetModel.shared
    @State private var calendar = CalendarModel.shared
    @State private var clips = ClipboardModel.shared
    @State private var focus = FocusTimer.shared
    @AppStorage("notchEnabled") private var notchEnabled = true
    @AppStorage("notchAllDisplays") private var allDisplays = false
    @AppStorage("notchExpandOnHover") private var expandOnHover = true
    @AppStorage("hudReplace") private var hudReplace = false
    @AppStorage("clipboardEnabled") private var clipboardEnabled = true
    @AppStorage("calendarEnabled") private var calendarEnabled = true
    @AppStorage(PetModel.Keys.hidden) private var petHidden = false
    @AppStorage(PetModel.Keys.quiet) private var petQuiet = false
    @AppStorage(PetModel.Keys.name) private var petName = "Gob"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = MediaKeyTap.isTrusted
    @State private var confirmRehatch = false
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    GobView(mood: pet.mood, genome: pet.genome, stage: pet.stats.stage, size: 60)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.black))
                        .onTapGesture { pet.send(.petted) }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("\(pet.genome.species.displayName) · Level \(pet.stats.level)").font(.headline)
                            RarityChip(rarity: pet.genome.rarity, shiny: pet.genome.shiny).scaleEffect(0.8)
                        }
                        Text("\(pet.stats.filesGobbled) files gobbled · \(pet.stats.burps) burps · petted \(pet.stats.pets)×")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("Name", text: $petName)
                Toggle("Show pet", isOn: Binding(get: { !petHidden }, set: { petHidden = !$0 }))
                Toggle("Quiet mode", isOn: $petQuiet)
                HStack {
                    Button("Share Pet Card…") { PetCard.share() }
                    Spacer()
                    Button("Hatch a New Egg…") { confirmRehatch = true }
                }
            } header: {
                Text("Pet")
            } footer: {
                Text("Quiet mode keeps \(pet.name) calm: no dancing or playful reactions.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notch") {
                Toggle("Show Gobbl in the notch", isOn: $notchEnabled)
                Toggle("Show on every display", isOn: $allDisplays)
                Toggle("Open when the pointer hovers over it", isOn: $expandOnHover)
            }

            Section {
                Toggle("Show volume, brightness and Caps Lock in the notch", isOn: $hudReplace)
                    .onChange(of: hudReplace) { _, on in
                        if on && !MediaKeyTap.isTrusted { MediaKeyTap.requestTrust() }
                        HUDService.apply()
                    }
                if hudReplace && !trusted {
                    HStack {
                        Label("Needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings") {
                            MediaKeyTap.requestTrust()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            } header: {
                Text("Volume & Brightness")
            } footer: {
                Text("Hold ⌥⇧ while pressing a key for finer steps.").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep clipboard history", isOn: $clipboardEnabled)
                LabeledContent("Open clipboard", value: "⇧⌘Space")
                Button("Clear History (keeps pinned)") { clips.clearUnpinned() }
                    .disabled(clips.history.items.isEmpty)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Stored only on this Mac. Items that password managers mark as concealed are never saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Calendar") {
                if calendar.authorized {
                    Toggle("Show my next meeting", isOn: $calendarEnabled)
                        .onChange(of: calendarEnabled) { _, on in
                            if on { calendar.start() } else { calendar.stop() }
                        }
                } else {
                    HStack {
                        Text("Show your next meeting and get a nudge before it starts.")
                        Spacer()
                        Button("Allow…") { Task { await calendar.requestAccess() } }
                    }
                }
            }

            Section("Focus Timer") {
                Stepper("Focus: \(focus.focusMinutes) min", value: Binding(get: { focus.focusMinutes }, set: { focus.focusMinutes = $0 }),
                        in: 5...120, step: 5)
                Stepper("Break: \(focus.restMinutes) min", value: Binding(get: { focus.restMinutes }, set: { focus.restMinutes = $0 }),
                        in: 1...30)
            }

            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Button("Show Welcome Tour…") { Onboarding.show() }
            }

            UpdatesSettingsSection()

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                Link("gobbl.xeve.io", destination: URL(string: "https://gobbl.xeve.io")!)
                Text("Free and open source (MIT) by Xeve. Now Playing uses mediaremote-adapter, © 2025 Jonas van den Berg, BSD 3-Clause License.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 620)
        .onReceive(poll) { _ in trusted = MediaKeyTap.isTrusted }
        .confirmationDialog("Hatch a new egg?", isPresented: $confirmRehatch) {
            Button("Hatch", role: .destructive) { pet.rehatch() }
        } message: {
            Text("\(pet.name), their level and their stats are replaced by a new pet. This can't be undone.")
        }
    }
}
