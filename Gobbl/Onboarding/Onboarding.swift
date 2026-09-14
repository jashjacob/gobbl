import AppKit
import GobblCore
import ServiceManagement
import SwiftUI

/// First run: hatch the egg (the reveal people screenshot), grant optional
/// permissions, learn the three gestures. Every permission is skippable.
@MainActor
enum Onboarding {
    private static var window: NSWindow?

    static func showIfNeeded() {
        if !UserDefaults.standard.bool(forKey: "onboarded") { show() }
    }

    static func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.contentView = NSHostingView(rootView: OnboardingView(done: finish))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        window?.close()
        window = nil
        NotchController.shared.open(tab: .home, focus: false)
    }
}

struct OnboardingView: View {
    let done: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: HatchStep { withAnimation(.gob) { step = 1 } }
                case 1: PermissionsStep()
                default: TipsStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            if step > 0 {
                HStack {
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Circle().fill(i == step ? Palette.accent : Palette.wellHover).frame(width: 6, height: 6)
                        }
                    }
                    Spacer()
                    Button(step == 2 ? "Let's go" : "Continue") {
                        if step == 2 { done() } else { withAnimation(.gob) { step += 1 } }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 520, height: 480)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.accent))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.gob, value: configuration.isPressed)
    }
}

// MARK: - Hatch

private struct HatchStep: View {
    let next: () -> Void
    @State private var pet = PetModel.shared
    @State private var phase = 0 // 0 egg, 1 cracking, 2 hatched
    @AppStorage(PetModel.Keys.name) private var name = "Gob"

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if phase < 2 {
                    EggView(hue: pet.genome.species.hue, cracking: phase == 1)
                        .frame(width: 140, height: 170)
                        .transition(.scale(scale: 1.3).combined(with: .opacity))
                } else {
                    GobView(mood: pet.mood, genome: pet.genome, stage: 0, size: 180)
                        .onTapGesture { pet.send(.petted) }
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .frame(height: 200)

            if phase < 2 {
                Text("Something's hatching…").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("A little creature wants to move into your notch.")
                    .font(.system(size: 13.5)).foregroundStyle(Palette.textSecondary)
                Button("Hatch it") { hatch() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(phase == 1)
                    .padding(.top, 8)
            } else {
                HStack(spacing: 10) {
                    Text("It's a \(pet.genome.shiny ? "shiny " : "")\(pet.genome.species.displayName)!")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    RarityChip(rarity: pet.genome.rarity, shiny: pet.genome.shiny)
                }
                Text(rarityLine).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                HStack(spacing: 10) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 170)
                    Button("That's my pet", action: next)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
        }
    }

    private var rarityLine: String {
        if pet.genome.shiny { return "Only 1 in 100 eggs hatch shiny. Show it off." }
        switch pet.genome.species.rarity {
        case .legendary: return "1 in 100 eggs. You lucky thing."
        case .rare: return "Only 1 in 20 eggs hatch one of these."
        case .uncommon: return "1 in 10 eggs. Nice."
        case .common: return "Give them a name. You can pet them any time."
        }
    }

    private func hatch() {
        withAnimation(.easeIn(duration: 0.2)) { phase = 1 }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { phase = 2 }
            pet.send(.celebrate)
        }
    }
}

/// A speckled egg that wobbles, then shakes and cracks.
private struct EggView: View {
    let hue: Double
    let cracking: Bool

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Idle: a wobble every couple of seconds. Cracking: a fast shake.
            let wobble = cracking ? sin(t * 38) * 0.14 : sin(t * 9) * 0.08 * max(0, sin(t * 1.3))
            Canvas { c, size in
                let w = size.width, h = size.height
                var egg = Path()
                egg.move(to: CGPoint(x: w / 2, y: 0))
                egg.addCurve(to: CGPoint(x: w, y: h * 0.62), control1: CGPoint(x: w * 0.86, y: 0), control2: CGPoint(x: w, y: h * 0.32))
                egg.addCurve(to: CGPoint(x: w / 2, y: h), control1: CGPoint(x: w, y: h * 0.88), control2: CGPoint(x: w * 0.78, y: h))
                egg.addCurve(to: CGPoint(x: 0, y: h * 0.62), control1: CGPoint(x: w * 0.22, y: h), control2: CGPoint(x: 0, y: h * 0.88))
                egg.addCurve(to: CGPoint(x: w / 2, y: 0), control1: CGPoint(x: 0, y: h * 0.32), control2: CGPoint(x: w * 0.14, y: 0))
                c.fill(egg, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFF6E6), Color(hex: 0xE9D9BE)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
                for (x, y, r) in [(0.3, 0.35, 0.07), (0.62, 0.25, 0.05), (0.68, 0.6, 0.08), (0.36, 0.72, 0.05), (0.5, 0.5, 0.04)] {
                    c.fill(Path(ellipseIn: CGRect(x: w * x - w * r, y: h * y - w * r, width: w * r * 2, height: w * r * 2)),
                           with: .color(Color(hue: hue, saturation: 0.55, brightness: 0.95)))
                }
                if cracking {
                    var crack = Path()
                    crack.move(to: CGPoint(x: w * 0.08, y: h * 0.48))
                    for (i, x) in stride(from: 0.18, through: 0.92, by: 0.1).enumerated() {
                        crack.addLine(to: CGPoint(x: w * x, y: h * (i.isMultiple(of: 2) ? 0.42 : 0.52)))
                    }
                    c.stroke(crack, with: .color(Color(hex: 0x6B5A40)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .rotationEffect(.radians(wobble), anchor: .bottom)
        }
    }
}

// MARK: - Permissions

private struct PermissionsStep: View {
    @State private var pet = PetModel.shared
    @State private var calendar = CalendarModel.shared
    @State private var trusted = MediaKeyTap.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Give \(pet.name) some superpowers").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("All optional. Nothing leaves your Mac.")
                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                .padding(.bottom, 6)
            PermissionRow(symbol: "speaker.wave.2.fill", title: "Volume & brightness in the notch",
                          detail: "Replaces the system popups. Needs Accessibility.", granted: trusted) {
                UserDefaults.standard.set(true, forKey: "hudReplace")
                MediaKeyTap.requestTrust()
            }
            PermissionRow(symbol: "calendar", title: "Your next meeting",
                          detail: "Gob nudges you five minutes before it starts.", granted: calendar.authorized) {
                Task { await calendar.requestAccess() }
            }
            PermissionRow(symbol: "power", title: "Open at login",
                          detail: "So Gob is there every morning.", granted: launchAtLogin) {
                try? SMAppService.mainApp.register()
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(poll) { _ in
            let now = MediaKeyTap.isTrusted
            guard now != trusted else { return }
            trusted = now
            HUDService.apply()
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.well))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.accent)
            } else {
                Button("Allow", action: action).controlSize(.large)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.well))
    }
}

// MARK: - Tips

private struct TipsStep: View {
    @State private var pet = PetModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How \(pet.name) helps").font(.system(size: 22, weight: .bold, design: .rounded))
            tip("tray.and.arrow.down.fill", "Drop files on the notch", "Gob keeps them on the shelf until you drag them out. Right-click a file to convert, compress or copy its text.")
            tip("doc.on.clipboard.fill", "⇧⌘Space opens your clipboard", "Everything you copied, searchable. Passwords are never saved.")
            tip("hand.tap.fill", "Hover the notch, click Gob", "Music, your next meeting, a focus timer, and one very happy pet.")
            tip("square.and.arrow.up.fill", "Show off your pet", "Right-click Gob to share their card.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
