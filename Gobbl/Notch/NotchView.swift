import GobblCore
import SwiftUI
import UniformTypeIdentifiers

/// The overlay's content. Collapsed: Gob in the left wing, status in the
/// right, or a HUD across both. Expanded: tabs beside the camera housing and
/// the selected panel below. The whole shape is a drop target.
struct NotchView: View {
    @Bindable var state: NotchState
    @State private var pet = PetModel.shared
    @State private var hud = HUDModel.shared
    @AppStorage(PetModel.Keys.hidden) private var petHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Extra width per wing while a HUD shows.
    static let hudExtra: CGFloat = 36

    private var g: NotchGeometry { state.geometry }
    private var showHUD: Bool { hud.current != nil && !state.expanded }

    private var size: CGSize {
        if state.expanded { return g.expandedSize }
        var s = g.collapsedSize
        if showHUD { s.width += 2 * Self.hudExtra }
        return s
    }

    private var flare: CGFloat { g.hasNotch ? NotchGeometry.flare : 0 }
    private var radius: CGFloat { state.expanded ? 26 : (g.hasNotch ? 12 : NotchGeometry.pillHeight / 2) }
    private var shape: NotchShape { NotchShape(flare: flare, radius: radius, attached: g.hasNotch) }
    private var sideWidth: CGFloat { max(0, (size.width - g.notchWidth) / 2) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                VStack(spacing: 0) {
                    band
                    if state.expanded {
                        panel
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 14)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, flare)
            }
            .frame(width: size.width + 2 * flare, height: size.height)
            .clipShape(shape)
            .overlay {
                if state.dropTargeted {
                    shape.stroke(Palette.accent.opacity(0.9), lineWidth: 1.5)
                } else if !g.hasNotch {
                    shape.stroke(Palette.border, lineWidth: 1)
                }
            }
            // Radius 0 when collapsed: a transparent shadow still costs a blur on every redraw.
            .shadow(color: .black.opacity(state.expanded ? 0.55 : 0), radius: state.expanded ? 18 : 0, y: state.expanded ? 10 : 0)
            .contentShape(shape)
            .onDrop(of: [.fileURL], isTargeted: $state.dropTargeted) { providers in
                ShelfModel.shared.accept(providers)
                return true
            }
            Spacer(minLength: 0)
        }
        .frame(width: g.canvas.width, height: g.canvas.height, alignment: .top)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.8), value: state.expanded)
        .animation(.gob, value: showHUD)
        .animation(.gob, value: g)
        .onChange(of: state.dropTargeted) { _, targeted in
            if targeted { state.tab = .shelf }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var panel: some View {
        switch state.tab {
        case .home: HomePanel(state: state)
        case .chat: ChatPanel()
        case .shelf: ShelfPanel(dropTargeted: state.dropTargeted)
        case .clipboard: ClipboardPanel(state: state)
        case .agents: AgentsPanel()
        case .tools: ToolsPanel()
        case .edit: EditPanel()
        }
    }

    // MARK: Band

    @ViewBuilder
    private var band: some View {
        Group {
            if g.hasNotch {
                HStack(spacing: 0) {
                    leading
                        .frame(width: sideWidth, alignment: .leading)
                    Color.clear.frame(width: g.notchWidth)
                    trailing
                        .frame(width: sideWidth, alignment: .trailing)
                }
                .frame(height: g.barHeight)
            } else {
                HStack(spacing: 8) {
                    leading
                    Spacer(minLength: 4)
                    trailing
                }
                .padding(.horizontal, 12)
                .frame(height: NotchGeometry.pillHeight)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !state.expanded { state.window?.toggle() }
        }
    }

    private var inset: CGFloat { g.hasNotch ? 14 : 0 }

    @ViewBuilder
    private var leading: some View {
        if state.expanded {
            TabBar(selection: $state.tab)
                .padding(.leading, g.hasNotch ? 16 : 0)
        } else if let h = hud.current {
            Image(systemName: h.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(h.tint ?? .white)
                .contentTransition(.symbolEffect(.replace))
                .padding(.leading, inset)
        } else if petHidden {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.dropTargeted ? Palette.accent : Palette.textSecondary)
                .padding(.leading, inset)
        } else {
            GobView(mood: pet.mood, genome: pet.genome, stage: pet.stats.stage, size: g.headerHeight - 4, hat: pet.hat,
                    anticipating: state.dropTargeted, lively: false, tracking: pet.lookActive,
                    look: { pet.look }, lookY: { pet.lookY })
                .padding(.leading, g.hasNotch ? 12 : 0)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if state.expanded {
            HStack(spacing: 4) {
                IconButton(symbol: "brain.head.profile", help: "Memory: to-dos, people and search") {
                    state.window?.close()
                    MemoryWindow.show()
                }
                IconButton(symbol: "gearshape.fill", help: "Settings") {
                    state.window?.close()
                    AppActions.openSettings()
                }
            }
            .padding(.trailing, g.hasNotch ? 16 : 0)
        } else if let h = hud.current {
            HUDReadout(hud: h)
                .padding(.trailing, inset)
        } else {
            StatusWing()
                .padding(.trailing, inset)
        }
    }
}

// MARK: - Collapsed pieces

private struct HUDReadout: View {
    let hud: HUDModel.HUD

    var body: some View {
        Group {
            if let value = hud.value {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(hud.tint ?? .white)
                            .frame(width: max(4, geo.size.width * value))
                    }
                }
                .frame(width: 52, height: 5)
                .animation(.easeOut(duration: 0.12), value: value)
            } else if let label = hud.label {
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(hud.tint ?? .white)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Right wing at rest: the focus timer if running, else music, else the shelf count.
private struct StatusWing: View {
    @State private var focus = FocusTimer.shared
    @State private var media = MediaController.shared
    @State private var shelf = ShelfModel.shared
    @State private var awake = KeepAwake.shared
    @State private var agents = AgentHub.shared
    @State private var memory = MemoryModel.shared

    var body: some View {
        HStack(spacing: 5) {
            if memory.isCapturing {
                // Always visible while Gobbl remembers the screen.
                Circle()
                    .fill(Palette.accent.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .help("Gobbl is remembering what's on screen. Pause it in Settings → Memory.")
            }
            if agents.anyWaiting {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.gold)
            } else if agents.tracker.anyWorking {
                Image(systemName: "sparkles")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                let busy = agents.sessions.filter(\.isWorking).count
                if busy > 1 { Text("\(busy)").font(.mono(11.5, weight: .semibold)) }
            } else if focus.isRunning {
                Image(systemName: focus.phase == .rest ? "cup.and.saucer.fill" : "timer")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clock(focus.remaining(at: context.date)))
                        .font(.mono(11.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else if media.nowPlaying.playing {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            } else if !shelf.items.isEmpty {
                Image(systemName: "tray.full.fill").font(.system(size: 10, weight: .semibold))
                Text("\(shelf.items.count)").font(.mono(11.5, weight: .semibold))
            }
            if awake.isOn {
                Image(systemName: "cup.and.heat.waves.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.gold)
            }
        }
        .foregroundStyle(Palette.textSecondary)
        .fixedSize()
    }
}

func clock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded()))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}

private struct TabBar: View {
    @Binding var selection: NotchTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.bar) { tab in
                Button {
                    selection = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == tab ? Palette.text : Palette.textTertiary)
                        .frame(width: 30, height: 22)
                        .background(Capsule().fill(selection == tab ? Palette.wellHover : .clear))
                        .overlay(alignment: .topTrailing) {
                            if tab == .chat && ChatModel.shared.unread {
                                Circle().fill(Palette.accent).frame(width: 5, height: 5).offset(x: -5, y: 3)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }
}
