import AppKit
import GobblCore

/// The morning brief, the evening wrap and nudges. A one-minute check is
/// all it costs; the AI is called at most twice a day for briefs, and nudges
/// are local rules with no AI at all.
@MainActor
final class Routines {
    static let shared = Routines()

    enum Keys {
        static let morning = "briefMorning"
        static let morningTime = "briefMorningMinute"
        static let evening = "briefEvening"
        static let eveningTime = "briefEveningMinute"
        static let nudges = "nudgesEnabled"
    }

    private var timer: Timer?
    private var running: Set<BriefKind> = []
    private var policy: NudgePolicy = {
        guard let data = UserDefaults.standard.data(forKey: "nudgePolicy"),
              let policy = try? JSONDecoder().decode(NudgePolicy.self, from: data) else { return NudgePolicy() }
        return policy
    }()

    static func enabled(_ kind: BriefKind) -> Bool {
        UserDefaults.standard.object(forKey: kind == .morning ? Keys.morning : Keys.evening) as? Bool ?? true
    }

    static func minuteOfDay(_ kind: BriefKind) -> Int {
        UserDefaults.standard.object(forKey: kind == .morning ? Keys.morningTime : Keys.eveningTime) as? Int
            ?? (kind == .morning ? 8 * 60 : 16 * 60 + 30)
    }

    func start() {
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { Routines.shared.tick() }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard !Self.screenLocked else { return }
        let now = Date()
        for kind in BriefKind.allCases where Self.enabled(kind) && AIClient.shared.isRegistered {
            let last = UserDefaults.standard.object(forKey: "briefLast.\(kind.rawValue)") as? Date
            if BriefSchedule.isDue(minuteOfDay: Self.minuteOfDay(kind), lastRun: last, now: now, calendar: .current) {
                runBrief(kind)
            }
        }
        checkNudges(now)
    }

    /// Scheduled, or asked for in chat ("brief me").
    func runBrief(_ kind: BriefKind) {
        guard !running.contains(kind) else { return }
        guard AIClient.shared.isRegistered else {
            ChatModel.shared.reply("Turn on AI in Settings for briefs.")
            return
        }
        running.insert(kind)
        UserDefaults.standard.set(Date(), forKey: "briefLast.\(kind.rawValue)")
        PetModel.shared.send(.assistantBusy(true))
        Task {
            defer {
                running.remove(kind)
                PetModel.shared.send(.assistantBusy(false))
            }
            do {
                let text = try await AIClient.shared.complete("/v1/brief", body: ["kind": kind.rawValue, "context": ChatContext.build(),
                                                                                  "locale": AIClient.locale])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                ChatModel.shared.addBrief(kind, text)
                HUDModel.shared.show(.init(symbol: kind == .morning ? "sun.horizon.fill" : "moon.stars.fill", label: kind.title,
                                           tint: Palette.accent), for: 6)
                PetModel.shared.send(.alert)
            } catch {
                ChatModel.shared.note("\(kind.title) didn't arrive: \((error as? AIClient.AIError)?.errorDescription ?? error.localizedDescription)",
                                      symbol: "exclamationmark.triangle")
            }
        }
    }

    // MARK: Nudges

    private func checkNudges(_ now: Date) {
        guard UserDefaults.standard.object(forKey: Keys.nudges) as? Bool ?? true else { return }
        let quiet = UserDefaults.standard.bool(forKey: PetModel.Keys.quiet)
        let focusing = FocusTimer.shared.isRunning && FocusTimer.shared.phase == .focus

        // An agent has been waiting on you for five minutes.
        for session in AgentHub.shared.sessions {
            guard case .waiting(let why) = session.state, now.timeIntervalSince(session.updated) > 5 * 60 else { continue }
            let key = "agent-\(session.id)-\(Int(session.updated.timeIntervalSince1970))"
            nudge(key, "\(session.project) has been waiting 5 minutes: \(why.lowercased())", symbol: "exclamationmark.bubble.fill",
                  now: now, quiet: quiet, focusing: focusing)
        }

        // A meeting in 15 minutes while you're deep in something else.
        if let next = CalendarModel.shared.next, next.start > now, next.start.timeIntervalSince(now) < 15 * 60 {
            let key = "meeting-\(next.id)"
            nudge(key, "\(next.title) starts at \(next.start.formatted(date: .omitted, time: .shortened))", symbol: "calendar",
                  now: now, quiet: quiet, focusing: false)
        }
    }

    private func nudge(_ key: String, _ text: String, symbol: String, now: Date, quiet: Bool, focusing: Bool) {
        guard policy.canNudge(key, now: now, quiet: quiet, focusing: focusing, calendar: .current) else { return }
        policy.record(key, now: now, calendar: .current)
        if let data = try? JSONEncoder().encode(policy) { UserDefaults.standard.set(data, forKey: "nudgePolicy") }
        ChatModel.shared.note(text, symbol: symbol)
        HUDModel.shared.show(.init(symbol: symbol, label: String(text.prefix(16)), tint: Palette.gold), for: 5)
        PetModel.shared.send(.alert)
    }

    private static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
