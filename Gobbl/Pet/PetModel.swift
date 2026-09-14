import AppKit
import GobblCore
import IOKit.ps
import Observation

/// The app's single Gob: genome and stats (persisted), the brain, and the
/// system signals that feed it. Sampling is deliberately slow (every 15 s);
/// anything faster comes from events.
@MainActor @Observable
final class PetModel {
    static let shared = PetModel()

    private(set) var genome: PetGenome
    private(set) var brain: MascotBrain
    private(set) var mood: Mood = .idle
    /// −1…1: where the cursor is, horizontally, relative to Gob. Read every
    /// animation frame, so it is not observed (no SwiftUI invalidation per mouse move).
    @ObservationIgnored var look: CGFloat = 0
    /// DEBUG `--mood`: pins the drawn mood, for screenshots.
    @ObservationIgnored var debugMood: Mood? {
        didSet { refresh() }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        let genome = d.data(forKey: Keys.genome).flatMap { try? JSONDecoder().decode(PetGenome.self, from: $0) }
            ?? PetGenome.hatch(seed: .random(in: .min ... .max))
        var stats = d.data(forKey: Keys.stats).flatMap { try? JSONDecoder().decode(MascotStats.self, from: $0) }
            ?? MascotStats()
        if stats.hatched == nil { stats.hatched = Date() }
        self.genome = genome
        brain = MascotBrain(stats: stats)
        brain.quiet = d.bool(forKey: Keys.quiet)
        save()
    }

    var stats: MascotStats { brain.stats }
    var name: String { defaults.string(forKey: Keys.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Gob" }

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
        let xp = brain.stats.xp
        brain.handle(signal)
        if case .petted = signal {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if brain.stats.xp != xp { save() }
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
        save()
        send(.celebrate)
    }

    // MARK: Private

    private func sample() {
        brain.quiet = defaults.bool(forKey: Keys.quiet)
        // kCGAnyInputEventType
        if let any = CGEventType(rawValue: ~0) {
            brain.handle(.userIdle(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)))
        }
        if let b = Battery.read() {
            brain.handle(.battery(level: b.level, charging: b.charging))
        }
        refresh()
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
    }
}
