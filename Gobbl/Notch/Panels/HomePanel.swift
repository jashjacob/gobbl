import GobblCore
import SwiftUI

/// Gob's corner, what's playing, and the next meeting.
struct HomePanel: View {
    let state: NotchState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PetCorner(anticipating: state.dropTargeted)
                .frame(width: 128)
            Rectangle().fill(Palette.border).frame(width: 1)
            // The panel's height is fixed; with to-dos the cards can outgrow it, so scroll
            // rather than clip. Bounces only when there's actually more to see.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    NowPlayingCard()
                    EventCard()
                    TodoCard()
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity)
        }
    }
}

struct PetCorner: View {
    let anticipating: Bool
    @State private var pet = PetModel.shared
    @AppStorage(PetModel.Keys.hidden) private var petHidden = false

    var body: some View {
        VStack(spacing: 5) {
            if petHidden {
                Image(systemName: "eye.slash").font(.system(size: 26)).foregroundStyle(Palette.textTertiary)
                    .frame(height: 84)
            } else {
                GobView(mood: pet.mood, genome: pet.genome, stage: pet.stats.stage, size: 84, hat: pet.hat,
                        anticipating: anticipating, look: { pet.look }, lookY: { pet.lookY })
                    .onTapGesture { pet.send(.petted) }
                    .help("Pet \(pet.name)")
                    .contextMenu {
                        Button("Pet \(pet.name)") { pet.send(.petted) }
                        Menu("Character") {
                            ForEach(PetCharacter.allCases) { character in
                                Button {
                                    pet.character = character
                                } label: {
                                    if pet.character == character { Label(character.title, systemImage: "checkmark") } else { Text(character.title) }
                                }
                            }
                        }
                        Menu("Skin") {
                            Button {
                                pet.skinID = nil
                            } label: {
                                if pet.skinID == nil { Label("Species colours", systemImage: "checkmark") } else { Text("Species colours") }
                            }
                            ForEach(SkinLibrary.shared.all) { skin in
                                Button {
                                    pet.skinID = skin.id
                                } label: {
                                    if pet.skinID == skin.id { Label(skin.name, systemImage: "checkmark") } else { Text(skin.name) }
                                }
                            }
                            if let skin = pet.skin {
                                Divider()
                                Button("Share “\(skin.name)”…") { SkinLibrary.shared.share(skin) }
                            }
                        }
                        WardrobeMenu()
                        Divider()
                        Button("Share \(pet.name)'s Card…") { PetCard.share() }
                        Menu("Make a Clip") {
                            ForEach(ClipStudio.Scene.allCases) { scene in
                                Button(scene.title) { ClipStudio.export(scene) }
                            }
                        }
                        Button("Record My Notch (6 s)…") { NotchRecorder.shared.record() }
                    }
            }
            HStack(spacing: 4) {
                Text(pet.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                if pet.genome.shiny { Text("✦").font(.system(size: 10)).foregroundStyle(Palette.gold) }
            }
            Text("\(pet.genome.species.displayName) · \(pet.genome.rarity.rawValue)")
                .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
            VStack(spacing: 3) {
                HStack {
                    Text("Lv \(pet.stats.level)").font(.mono(10, weight: .semibold)).foregroundStyle(Palette.accent)
                    Spacer()
                    Text("\(pet.stats.filesGobbled) gobbled").font(.mono(9.5)).foregroundStyle(Palette.textTertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.well)
                        Capsule().fill(Palette.accent).frame(width: max(3, geo.size.width * pet.stats.levelProgress))
                    }
                }
                .frame(height: 3)
            }
        }
    }
}

/// Hats: owned ones to wear, locked ones with how to earn them.
struct WardrobeMenu: View {
    @State private var pet = PetModel.shared

    var body: some View {
        let owned = pet.ownedHats
        Menu("Wardrobe") {
            ForEach(Hat.allCases) { hat in
                if owned.contains(hat) {
                    Button {
                        pet.hat = hat
                    } label: {
                        if pet.hat == hat { Label(hat.title, systemImage: "checkmark") } else { Text(hat.title) }
                    }
                } else {
                    Button("🔒 \(hat.title) — \(hat.requirement)") {}
                        .disabled(true)
                }
            }
        }
    }
}

// MARK: - Now playing

struct NowPlayingCard: View {
    @State private var media = MediaController.shared

    var body: some View {
        let n = media.nowPlaying
        HStack(spacing: 11) {
            artwork
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture { media.openPlayer() }
                .help(media.appName.map { "Open \($0)" } ?? "")
            VStack(alignment: .leading, spacing: 3) {
                if n.hasMedia {
                    Text(n.title ?? "")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    SubtitleLine(nowPlaying: n, fallback: n.artist ?? media.appName ?? "")
                    ProgressRow(nowPlaying: n)
                    HStack(spacing: 16) {
                        IconButton(symbol: "backward.fill", size: 11, tint: Palette.text) { media.previous() }
                        IconButton(symbol: n.playing ? "pause.fill" : "play.fill", size: 14, tint: Palette.text) {
                            media.togglePlayPause()
                        }
                        IconButton(symbol: "forward.fill", size: 11, tint: Palette.text) { media.next() }
                        OutputPicker()
                    }
                } else {
                    Text(media.available ? "Nothing playing" : "Now Playing unavailable")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(media.available ? "Play something. Gob loves to dance." : "A macOS update blocked media access.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.well))
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = media.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else if let icon = media.appIcon {
            Image(nsImage: icon).resizable().padding(6).background(Palette.well)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.well)
        }
    }
}

/// The artist, or — with lyrics on and a synced match — the line being sung.
private struct SubtitleLine: View {
    let nowPlaying: NowPlaying
    let fallback: String
    @State private var lyrics = LyricsModel.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: lyrics.lines.isEmpty || !nowPlaying.playing)) { context in
            let line = lyrics.lines.isEmpty ? nil : lyrics.line(at: nowPlaying.elapsed(at: context.date) ?? 0)
            Text(line ?? fallback)
                .font(.system(size: 11, weight: line == nil ? .regular : .medium))
                .foregroundStyle(line == nil ? Palette.textSecondary : Palette.accent)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: line)
        }
    }
}

/// Where the sound goes: speakers, AirPods, AirPlay devices the system lists.
private struct OutputPicker: View {
    var body: some View {
        Menu {
            let current = AudioDevices.defaultOutput
            ForEach(AudioDevices.outputs()) { device in
                Button {
                    AudioDevices.setDefaultOutput(device.id)
                    HUDModel.shared.show(.init(symbol: "hifispeaker.fill", label: String(device.name.prefix(12)), tint: Palette.accent))
                } label: {
                    if device.id == current { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
        } label: {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sound output")
    }
}

private struct ProgressRow: View {
    let nowPlaying: NowPlaying

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !nowPlaying.playing)) { context in
            let elapsed = nowPlaying.elapsed(at: context.date) ?? 0
            let duration = nowPlaying.duration ?? 0
            HStack(spacing: 6) {
                Text(clock(elapsed)).font(.mono(9)).foregroundStyle(Palette.textTertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Palette.text)
                            .frame(width: duration > 0 ? max(3, geo.size.width * min(1, elapsed / duration)) : 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard duration > 0 else { return }
                        MediaController.shared.seek(to: duration * Double(location.x / geo.size.width))
                    }
                }
                .frame(height: 3)
                Text(duration > 0 ? clock(duration) : "–").font(.mono(9)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

// MARK: - Calendar

struct EventCard: View {
    @State private var calendar = CalendarModel.shared
    @AppStorage("calendarEnabled") private var enabled = true

    var body: some View {
        HStack(spacing: 10) {
            if !calendar.authorized || !enabled {
                Image(systemName: "calendar").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your next meeting, right here").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Gob nudges you 5 minutes before.").font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 4)
                PillButton(title: "Allow", symbol: "checkmark") {
                    enabled = true
                    Task { await calendar.requestAccess() }
                }
            } else if let event = calendar.next {
                RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.when(event, now: context.date)).font(.system(size: 10.5)).foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: 4)
                if let url = event.joinURL {
                    PillButton(title: "Join", symbol: "video.fill", prominent: true) {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.accent)
                Text("Nothing else on your calendar.").font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.well))
    }

    static func when(_ e: CalendarModel.Event, now: Date) -> String {
        let time = "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))"
        if e.start <= now { return "Now · until \(e.end.formatted(date: .omitted, time: .shortened))" }
        let minutes = Int((e.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "In \(minutes) min · \(time)" }
        if Calendar.current.isDateInToday(e.start) { return "Today · \(time)" }
        if Calendar.current.isDateInTomorrow(e.start) { return "Tomorrow · \(time)" }
        return e.start.formatted(date: .abbreviated, time: .shortened)
    }
}
