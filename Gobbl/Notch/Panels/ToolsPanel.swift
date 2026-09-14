import SwiftUI

/// Focus timer, plus a grid of one-click tools.
struct ToolsPanel: View {
    @State private var awake = KeepAwake.shared
    @State private var tools = QuickTools.shared
    @AppStorage(PetModel.Keys.quiet) private var quiet = false

    var body: some View {
        HStack(spacing: 10) {
            FocusCard()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ToolTile(symbol: "cup.and.heat.waves.fill", title: "Keep awake", isOn: awake.isOn) { awake.toggle() }
                ToolTile(symbol: tools.micMuted ? "mic.slash.fill" : "mic.fill", title: tools.micMuted ? "Mic muted" : "Mute mic",
                         isOn: tools.micMuted, onColor: .red) { tools.toggleMic() }
                ToolTile(symbol: "eyedropper.halffull", title: "Pick color", isOn: false) { tools.pickColor() }
                ToolTile(symbol: "text.viewfinder", title: "Screen text", isOn: false) { tools.captureScreenText() }
                ToolTile(symbol: "moon.fill", title: "Quiet pet", isOn: quiet) { quiet.toggle() }
                ShareTile()
            }
            .frame(width: 236)
        }
        .onAppear { tools.refreshMic() }
    }
}

private struct FocusCard: View {
    @State private var focus = FocusTimer.shared

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: focus.phase == .rest ? "cup.and.saucer.fill" : "timer")
                        .foregroundStyle(Palette.accent)
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    if focus.completedToday > 0 {
                        Text("\(focus.completedToday) today").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    }
                }
                TimelineView(.animation(minimumInterval: 1, paused: !focus.isRunning)) { context in
                    Text(clock(focus.remaining(at: context.date)))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(focus.isRunning ? Palette.text : Palette.textSecondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    PillButton(title: focus.isRunning ? "Pause" : (focus.pausedRemaining == nil ? "Start" : "Resume"),
                               symbol: focus.isRunning ? "pause.fill" : "play.fill", prominent: !focus.isRunning) {
                        focus.toggle()
                    }
                    if focus.phase != .idle {
                        PillButton(title: "Reset", symbol: "arrow.counterclockwise") { focus.reset() }
                    } else {
                        ForEach([25, 50], id: \.self) { minutes in
                            PillButton(title: "\(minutes)m", symbol: focus.focusMinutes == minutes ? "checkmark" : "clock") {
                                focus.focusMinutes = minutes
                            }
                        }
                    }
                }
            }
        }
    }

    private var title: String {
        switch focus.phase {
        case .idle: "Focus timer"
        case .focus: "Focusing"
        case .rest: "Break"
        }
    }
}

private struct ToolTile: View {
    let symbol: String
    let title: String
    let isOn: Bool
    var onColor: Color = Palette.accent
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TileLabel(symbol: symbol, title: title, isOn: isOn, onColor: onColor, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct TileLabel: View {
    let symbol: String
    let title: String
    let isOn: Bool
    var onColor: Color = Palette.accent
    let hovering: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Palette.textSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isOn ? onColor : Color.white.opacity(0.06)))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Palette.wellHover : Palette.well))
        .contentShape(Rectangle())
    }
}

/// Share menu: pet card, rendered scenes, or a real recording of the notch.
private struct ShareTile: View {
    @State private var pet = PetModel.shared
    @State private var hovering = false

    var body: some View {
        Menu {
            Button("Share \(pet.name)'s Card…") { PetCard.share() }
            Section("Make a Clip (MP4 + GIF)") {
                ForEach(ClipStudio.Scene.allCases) { scene in
                    Button(scene.title) { ClipStudio.export(scene) }
                }
            }
            Divider()
            Button("Record My Notch (6 s)…") { NotchRecorder.shared.record() }
        } label: {
            TileLabel(symbol: "sparkles.tv.fill", title: "Share \(pet.name)", isOn: false, hovering: hovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
    }
}
