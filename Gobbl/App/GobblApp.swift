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
            HUDService.apply()
            _ = Updater.shared // starts Sparkle's scheduled checks
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
            if args.contains("--onboarding") { Onboarding.show() }
            #endif
            if !args.contains("--expand") && !args.contains("--no-onboarding") { Onboarding.showIfNeeded() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            MediaController.shared.stop()
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
    /// An accessory app has to activate itself or Settings opens behind other windows.
    @MainActor static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
