import AppKit
import EventKit
import SwiftUI

/// The next few timed events, a Join link when the invite has one, and a
/// nudge from Gob five minutes before a meeting starts.
@MainActor @Observable
final class CalendarModel {
    static let shared = CalendarModel()

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: Color
        let joinURL: URL?
        /// Other people invited (names, or email addresses when there's no name).
        var attendees: [String] = []
    }

    private(set) var events: [Event] = []
    private(set) var authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var nudged: Set<String> = []

    var next: Event? { events.first }
    var enabled: Bool { UserDefaults.standard.object(forKey: "calendarEnabled") as? Bool ?? true }

    func start() {
        if authorized && enabled { begin() }
    }

    /// Asks only when the user chooses to (onboarding, the Home card, Settings).
    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authorized = granted
        if granted {
            UserDefaults.standard.set(true, forKey: "calendarEnabled")
            begin()
        }
    }

    #if DEBUG
    /// `--demo`: sample events for screenshots, without touching the real calendar.
    func setDemo(_ demo: [Event]) {
        stop()
        authorized = true
        events = demo
    }
    #endif

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        events = []
    }

    private func begin() {
        guard timer == nil else { return reload() }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        timer = t
        reload()
    }

    func reload() {
        guard authorized else { return }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .hour, value: 36, to: now) else { return }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-4 * 3600), end: end, calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)
            .map(Self.event(from:))
        if upcoming != events { events = Array(upcoming) }
        nudgeIfSoon(now)
    }

    private func nudgeIfSoon(_ now: Date) {
        guard let e = next, !nudged.contains(e.id) else { return }
        let lead = e.start.timeIntervalSince(now)
        guard lead > 0, lead <= 5 * 60 else { return }
        nudged.insert(e.id)
        PetModel.shared.send(.alert)
        HUDModel.shared.show(.init(symbol: "calendar.badge.clock", label: "\(Int((lead / 60).rounded(.up)))m",
                                   tint: Palette.gold), for: 5)
    }

    private static func event(from e: EKEvent) -> Event {
        Event(id: "\(e.eventIdentifier ?? e.title ?? "")@\(e.startDate.timeIntervalSince1970)",
              title: e.title ?? "Untitled", start: e.startDate, end: e.endDate,
              color: Color(cgColor: e.calendar.cgColor), joinURL: joinURL(e),
              attendees: (e.attendees ?? []).filter { !$0.isCurrentUser }.compactMap {
                  $0.name ?? $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
              })
    }

    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                       "webex.com", "whereby.com", "facetime.apple.com", "around.co"]

    /// A video-call link from the event's URL, location or notes.
    static func joinURL(_ e: EKEvent) -> URL? {
        func isMeeting(_ url: URL) -> Bool { meetingHosts.contains { url.host?.hasSuffix($0) ?? false } }
        if let url = e.url, isMeeting(url) { return url }
        let text = [e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url).first(where: isMeeting)
    }
}
