import SwiftUI

/// Focus timer, keep-awake and quick pet toggles.
struct ToolsPanel: View {
    var body: some View {
        HStack(spacing: 10) {
            FocusCard()
            VStack(spacing: 8) {
                KeepAwakeToggle()
                QuietToggle()
                ShareCardButton()
            }
            .frame(width: 186)
        }
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
                        Text("\(focus.completedToday) done today").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    }
                }
                TimelineView(.animation(minimumInterval: 1, paused: !focus.isRunning)) { context in
                    Text(clock(focus.remaining(at: context.date)))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(focus.isRunning ? Palette.text : Palette.textSecondary)
                }
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

private struct ToolToggle: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black : Palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isOn ? Palette.accent : Palette.well))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Palette.wellHover : Palette.well))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct KeepAwakeToggle: View {
    @State private var awake = KeepAwake.shared

    var body: some View {
        ToolToggle(symbol: "cup.and.heat.waves.fill", title: "Keep awake",
                   subtitle: awake.isOn ? "Display stays on" : "Off", isOn: awake.isOn) { awake.toggle() }
    }
}

private struct QuietToggle: View {
    @AppStorage(PetModel.Keys.quiet) private var quiet = false

    var body: some View {
        ToolToggle(symbol: "moon.fill", title: "Quiet pet",
                   subtitle: quiet ? "No dancing" : "Gob is lively", isOn: quiet) { quiet.toggle() }
    }
}

private struct ShareCardButton: View {
    @State private var pet = PetModel.shared

    var body: some View {
        ToolToggle(symbol: "square.and.arrow.up.fill", title: "Share \(pet.name)",
                   subtitle: "Save a pet card", isOn: false) { PetCard.share() }
    }
}
