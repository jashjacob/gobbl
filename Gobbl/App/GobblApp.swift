import AppKit
import Carbon.HIToolbox
import GobblCore
import SwiftUI

@main
struct GobblApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Gobbl", systemImage: "face.smiling.inverse") {
            MenuBarMenu()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeys: [HotKey] = []
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill`/logout send SIGTERM, which skips applicationWillTerminate:
        // clean up the adapter process and the power assertion ourselves.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    MediaController.shared.stop()
                    AgentHub.shared.stop()
                    KeepAwake.shared.set(false)
                }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        MainActor.assumeIsolated {
            PetModel.shared.start()
            NotchController.shared.start()
            MediaController.shared.start()
            ClipboardModel.shared.start()
            CalendarModel.shared.start()
            PowerMonitor.shared.start()
            AgentHub.shared.start()
            SystemEvents.shared.start()
            HUDService.apply()
            TypingMonitor.apply()
            _ = Updater.shared // starts Sparkle's scheduled checks
            RemoteFlags.refresh()
            if let clipboard = HotKey(keyCode: kVK_Space, modifiers: cmdKey | shiftKey, id: 1, action: {
                NotchController.shared.open(tab: .clipboard)
            }) {
                hotKeys.append(clipboard)
            }

            let args = CommandLine.arguments
            #if DEBUG
            // For screenshots: `Gobbl.app/Contents/MacOS/Gobbl --expand [--tab tools] [--mood dancing]`.
            if args.contains("--expand") {
                NotchController.shared.debugExpand()
                if let i = args.firstIndex(of: "--tab"), i + 1 < args.count, let tab = NotchTab(rawValue: args[i + 1]) {
                    NotchController.shared.open(tab: tab, focus: false)
                    NotchController.shared.debugExpand()
                }
            }
            if let i = args.firstIndex(of: "--mood"), i + 1 < args.count, let mood = Mood(rawValue: args[i + 1]) {
                PetModel.shared.debugMood = mood
            }
            if let i = args.firstIndex(of: "--render-card"), i + 1 < args.count {
                PetCard.render(to: URL(fileURLWithPath: args[i + 1]))
            }
            if let i = args.firstIndex(of: "--render-clip"), i + 2 < args.count,
               let scene = ClipStudio.Scene(rawValue: args[i + 1]) {
                let dir = URL(fileURLWithPath: args[i + 2])
                Task {
                    try? await ClipStudio.render(scene, video: dir.appendingPathComponent("\(scene.rawValue).mp4"),
                                                 gif: dir.appendingPathComponent("\(scene.rawValue).gif"))
                    exit(0)
                }
            }
            if let i = args.firstIndex(of: "--render-pets"), i + 1 < args.count {
                // Review sheet: every character in the key moods, as one PNG.
                let moods: [Mood] = [.idle, .eating, .thinking, .working, .love, .celebrating, .sleeping]
                let genome = PetModel.shared.genome
                let sheet = VStack(spacing: 14) {
                    ForEach(PetCharacter.allCases) { character in
                        HStack(spacing: 14) {
                            ForEach(moods, id: \.self) { mood in
                                VStack(spacing: 4) {
                                    GobView(mood: mood, genome: genome, stage: 1, size: 130, hat: .none, character: character,
                                            skin: nil, time: 1.3)
                                    Text("\(character.title) · \(mood.rawValue)").font(.caption).foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        // Unboxing, frame by frame.
                        ForEach([-1.0, 0.3, 0.9, 1.4, 2.0, 2.6, 3.2, 4.0], id: \.self) { e in
                            UnboxScene(elapsed: e, t: 1.3, pet: PetModel.shared)
                                .scaleEffect(0.62)
                                .frame(width: 165, height: 158)
                        }
                    }
                    HStack(spacing: 14) {
                        ForEach(Species.allCases, id: \.self) { species in
                            GobView(mood: .happy, genome: PetGenome(seed: 0, species: species, shiny: false), stage: 0, size: 100,
                                    hat: .party, character: .candy, skin: nil, time: 1.3)
                        }
                    }
                }
                .padding(24)
                .background(Color.black)
                let renderer = ImageRenderer(content: sheet)
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: args[i + 1]))
                }
                exit(0)
            }
            if args.contains("--onboarding") { Onboarding.show() }
            if args.contains("--settings") { AppActions.openSettings() }
            #endif
            if !args.contains("--expand") && !args.contains("--no-onboarding") { Onboarding.showIfNeeded() }
        }
    }

    /// Double-clicked .gobskin files.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls where url.pathExtension.lowercased() == PetSkin.fileExtension {
                SkinLibrary.shared.install(from: url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            MediaController.shared.stop()
            AgentHub.shared.stop()
            KeepAwake.shared.set(false)
        }
    }
}

struct MenuBarMenu: View {
    @State private var pet = PetModel.shared
    @State private var focus = FocusTimer.shared
    @State private var awake = KeepAwake.shared

    var body: some View {
        Text("\(pet.name) · \(pet.genome.species.displayName) · Level \(pet.stats.level)")
        Button("Pet \(pet.name)") { pet.send(.petted) }
        Button("Share \(pet.name)'s Card…") { PetCard.share() }
        Divider()
        Button("Open Clipboard (⇧⌘Space)") { NotchController.shared.open(tab: .clipboard) }
        Button("Open Shelf") { NotchController.shared.open(tab: .shelf, focus: false) }
        Button(focus.isRunning ? "Pause Focus Timer" : "Start Focus Timer") { focus.toggle() }
        Toggle("Keep Mac Awake", isOn: Binding(get: { awake.isOn }, set: { awake.set($0) }))
        Divider()
        Button("Welcome Tour…") { Onboarding.show() }
        CheckForUpdatesButton()
        Button("Settings…") { AppActions.openSettings() }
            .keyboardShortcut(",")
        Button("Quit Gobbl") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

enum AppActions {
    @MainActor static func openSettings() { SettingsWindow.show() }
}

/// Gobbl's Settings window, owned directly. Since macOS 14 the
/// `showSettingsWindow:` action is ignored unless it comes from a SwiftUI
/// SettingsLink, so an accessory app opening Settings from the notch or the
/// menu bar needs its own window.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Gobbl Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("GobblSettings")
            w.center()
            window = w
        }
        // An accessory app must activate itself or the window opens behind others.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
