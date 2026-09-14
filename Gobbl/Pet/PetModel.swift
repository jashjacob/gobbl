import AppKit
import GobblCore
import Observation

/// The app's single Gob: genome, stats and hat (persisted), the brain, and
/// the system signals that feed it. Sampling is deliberately slow (every
/// 15 s); anything faster comes from events.
@MainActor @Observable
final class PetModel {
    static let shared = PetModel()

    private(set) var genome: PetGenome
    private(set) var brain: MascotBrain
    private(set) var mood: Mood = .idle
    var hat: Hat {
        didSet { defaults.set(hat.rawValue, forKey: Keys.hat) }
    }
    var character: PetCharacter {
        didSet { defaults.set(character.rawValue, forKey: Keys.character) }
    }
    /// nil: the species colours.
    var skinID: String? {
        didSet { defaults.set(skinID, forKey: Keys.skin) }
    }
    var skin: PetSkin? { SkinLibrary.shared.skin(id: skinID) }
    /// −1…1: where the cursor is, horizontally, relative to Gob. Read every
    /// animation frame, so it is not observed (no SwiftUI invalidation per mouse move).
    @ObservationIgnored var look: CGFloat = 0
    /// DEBUG `--mood`: pins the drawn mood, for screenshots.
    @ObservationIgnored var debugMood: Mood? {
        didSet { refresh() }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var cpu = CPUSampler()
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        let genome = d.data(forKey: Keys.genome).flatMap { try? JSONDecoder().decode(PetGenome.self, from: $0) }
            ?? PetGenome.hatch(seed: .random(in: .min ... .max))
        var stats = d.data(forKey: Keys.stats).flatMap { try? JSONDecoder().decode(MascotStats.self, from: $0) }
            ?? MascotStats()
        if stats.hatched == nil { stats.hatched = Date() }
        var brain = MascotBrain(stats: stats)
        brain.quiet = d.bool(forKey: Keys.quiet)
        let savedHat = d.string(forKey: Keys.hat).flatMap(Hat.init(rawValue:)) ?? .none
        self.genome = genome
        self.brain = brain
        hat = Wardrobe.owned(stats: stats, date: Date()).contains(savedHat) ? savedHat : .none
        character = d.string(forKey: Keys.character).flatMap(PetCharacter.init(rawValue:)) ?? .gob
        skinID = d.string(forKey: Keys.skin)
        save()
    }

    var stats: MascotStats { brain.stats }
    var name: String { defaults.string(forKey: Keys.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Gob" }
    var ownedHats: [Hat] { Wardrobe.owned(stats: stats, date: Date()) }

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func send(_ signal: MascotSignal) {
        brain.quiet = defaults.bool(forKey: Keys.quiet)
        let before = brain.stats
        brain.handle(signal)
        if case .petted = signal {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if let milestone = MascotBrain.milestone(from: before.filesGobbled, to: brain.stats.filesGobbled) {
            brain.handle(.milestone)
            HUDModel.shared.show(.init(symbol: "party.popper.fill", label: "\(milestone) files!", tint: Palette.gold), for: 3)
        }
        checkWardrobe()
        if brain.stats != before { save() }
        refresh()
    }

    /// Called on user input: a sleeping Gob wakes straight away rather than at the next sample.
    func wakeIfSleeping() {
        guard mood == .sleeping else { return }
        brain.handle(.userIdle(0))
        refresh()
    }

    func rehatch() {
        genome = .hatch(seed: .random(in: .min ... .max))
        var stats = MascotStats()
        stats.hatched = Date()
        brain = MascotBrain(stats: stats)
        hat = .none
        save()
        send(.celebrate)
    }

    // MARK: Private

    private func sample() {
        brain.quiet = defaults.bool(forKey: Keys.quiet)
        // kCGAnyInputEventType
        let idle = CGEventType(rawValue: ~0).map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        } ?? 0
        brain.handle(.userIdle(idle))
        if let b = Battery.read() {
            brain.handle(.battery(level: b.level, charging: b.charging))
        }
        if let load = cpu.sample() {
            brain.handle(.cpuLoad(load))
        }
        // A day counts towards the streak once the user is actually at the Mac.
        if idle < 120, brain.stats.recordActiveDay(Date()) {
            checkWardrobe()
            save()
        }
        refresh()
    }

    /// Collects newly earned hats, puts the first one on, and makes a fuss about it.
    private func checkWardrobe() {
        let new = Wardrobe.newlyUnlocked(stats: brain.stats, date: Date())
        guard let first = new.first else { return }
        brain.stats.collected += new.map(\.rawValue)
        if hat == .none { hat = first }
        brain.handle(.celebrate)
        HUDModel.shared.show(.init(symbol: "gift.fill", label: first.title, tint: Palette.gold), for: 3.5)
        save()
    }

    private func refresh() {
        let now = Date()
        let m = debugMood ?? brain.mood(at: now)
        if m != mood { mood = m }
        refreshTask?.cancel()
        refreshTask = nil
        guard let next = brain.nextChange(after: now) else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSince(now) + 0.05))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func save() {
        let e = JSONEncoder()
        defaults.set(try? e.encode(genome), forKey: Keys.genome)
        defaults.set(try? e.encode(brain.stats), forKey: Keys.stats)
    }

    enum Keys {
        static let genome = "petGenome"
        static let stats = "petStats"
        static let quiet = "petQuiet"
        static let hidden = "petHidden"
        static let name = "petName"
        static let hat = "petHat"
        static let character = "petCharacter"
        static let skin = "petSkin"
    }
}

/// Whole-machine CPU load from host tick counters, as a delta between samples.
struct CPUSampler {
    private var previous: host_cpu_load_info?

    mutating func sample() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        defer { previous = info }
        guard let p = previous else { return nil }
        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)
        let total = user + system + idle + nice
        return total > 0 ? (user + system + nice) / total : nil
    }
}
