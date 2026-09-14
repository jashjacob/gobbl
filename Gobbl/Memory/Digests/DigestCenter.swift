import Foundation
import GobblCore
import Observation
import os

private let log = Logger(subsystem: "com.xeve.gobbl", category: "digests")

/// Day digests: after 5 am, yesterday gets summarised; after 9 pm, today.
/// The AI sees only short, already-masked excerpts of the windows used
/// most, grouped into morning, afternoon and evening, and answers with
/// at most three outcome bullets per part.
@MainActor @Observable
final class DigestCenter {
    static let shared = DigestCenter()

    /// The last 30 days, newest first.
    private(set) var digests: [DayDigest] = []
    private(set) var building = false

    @ObservationIgnored private var timer: Timer?

    private var store: MemoryStore? { MemoryModel.shared.store }
    private var calendar: Calendar { .current }

    func start() {
        reload()
        let timer = Timer(timeInterval: 900, repeats: true) { _ in
            MainActor.assumeIsolated { DigestCenter.shared.tick() }
        }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard MemoryModel.shared.isCapturing, AIClient.shared.isRegistered, !building, let store else { return }
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let today = DayParts.dayKey(now, calendar: calendar)
        let yesterday = DayParts.dayKey(now.addingTimeInterval(-86400), calendar: calendar)
        if hour >= 5, !store.hasDigest(day: yesterday), canTry(yesterday) {
            Task { await build(day: yesterday) }
        } else if hour >= 21, canTry(today), (lastBuilt[today] ?? .distantPast) < now.addingTimeInterval(-3 * 3600) {
            Task { await build(day: today) }
        }
    }

    /// Summarises one day. Also the "Summarise Today" button.
    func build(day: String) async {
        guard !building, let store, let range = DayParts.range(of: day, calendar: calendar) else { return }
        building = true
        defer { building = false }
        markTried(day)

        let segments = (try? store.segments(from: range.start, to: min(range.end, Date()))) ?? []
        var byPart: [String: [SegmentSummary]] = [:]
        for s in segments { byPart[DayParts.part(of: s.started, calendar: calendar), default: []].append(s) }

        var parts: [[String: Any]] = []
        var total = 0
        for part in DayParts.order {
            guard let list = byPart[part], list.reduce(0, { $0 + $1.minutes }) >= 3 else { continue }
            var items: [[String: Any]] = []
            for s in list.sorted(by: { $0.minutes > $1.minutes }).prefix(40) {
                let summary = String(s.excerpt.prefix(260))
                guard total + summary.count < 7500 else { break }
                total += summary.count
                var item: [String: Any] = ["app": s.app, "minutes": Int(s.minutes.rounded()), "summary": summary]
                if !s.window.isEmpty { item["window"] = String(s.window.prefix(120)) }
                if let chat = s.chat { item["chat"] = chat }
                if let domain = s.domain { item["url_domain"] = domain }
                items.append(item)
            }
            if !items.isEmpty { parts.append(["part": part, "segments": items]) }
        }
        guard !parts.isEmpty else { return }

        do {
            let result = try await AIClient.shared.json("/v1/digest", body: ["day": day, "parts": parts, "locale": AIClient.locale])
            for p in result["parts"] as? [[String: Any]] ?? [] {
                guard let part = p["part"] as? String, let bullets = p["bullets"] as? [String], !bullets.isEmpty else { continue }
                try? store.upsertDigest(DayDigest(day: day, part: part, bullets: bullets, apps: p["apps"] as? [String] ?? [], created: Date()))
            }
            var built = lastBuilt
            built[day] = Date()
            lastBuilt = built
            log.info("digest built for \(parts.count) parts")
        } catch {
            log.error("digest failed: \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }

    func reload() {
        guard let store else {
            digests = []
            return
        }
        let since = DayParts.dayKey(Date().addingTimeInterval(-30 * 86400), calendar: calendar)
        digests = (try? store.digests(sinceDay: since)) ?? []
    }

    /// "- " lines for one day, for the morning brief.
    func text(forDay day: String) -> String? {
        let lines = digests.filter { $0.day == day }.flatMap(\.bullets).map { "- \($0)" }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The windows behind one part of a day, for "Sources".
    func sources(day: String, part: String) -> [SegmentSummary] {
        guard let store, let range = DayParts.range(of: day, calendar: calendar) else { return [] }
        return ((try? store.segments(from: range.start, to: range.end, excerptChars: 140)) ?? [])
            .filter { DayParts.part(of: $0.started, calendar: calendar) == part }
    }

    func forget(segment id: Int64) {
        try? store?.forget(segment: id)
        MemoryModel.shared.refreshStats()
    }

    // MARK: Retry bookkeeping

    private var lastBuilt: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: "digestBuilt") as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue.filter { $0.value > Date().addingTimeInterval(-7 * 86400) }, forKey: "digestBuilt") }
    }

    /// At most one try every three hours per day, so a failure doesn't burn the allowance.
    private func canTry(_ day: String) -> Bool {
        let tried = (UserDefaults.standard.dictionary(forKey: "digestTried") as? [String: Date])?[day] ?? .distantPast
        return Date().timeIntervalSince(tried) > 3 * 3600
    }

    private func markTried(_ day: String) {
        var tried = (UserDefaults.standard.dictionary(forKey: "digestTried") as? [String: Date]) ?? [:]
        tried = tried.filter { $0.value > Date().addingTimeInterval(-7 * 86400) }
        tried[day] = Date()
        UserDefaults.standard.set(tried, forKey: "digestTried")
    }
}
