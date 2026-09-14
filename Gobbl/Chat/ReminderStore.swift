import AppKit
import GobblCore
import Observation
import UserNotifications

/// Reminders set from chat. One timer aimed at the next one (no polling),
/// re-aimed after sleep. Stored as a small JSON file on this Mac.
@MainActor @Observable
final class ReminderStore {
    static let shared = ReminderStore()

    private(set) var reminders: [Reminder] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var askedForNotifications = false

    private static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Gobbl/reminders.json")

    var open: [Reminder] { reminders.filter { !$0.done }.sorted { $0.due < $1.due } }

    func start() {
        load()
        schedule()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ReminderStore.shared.fireDue() }
        }
    }

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
        save()
        schedule()
        requestNotificationsOnce()
    }

    func cancel(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        save()
        schedule()
    }

    // MARK: Firing

    private func schedule() {
        timer?.invalidate()
        guard let next = open.first else { return }
        let timer = Timer(timeInterval: max(0.5, next.due.timeIntervalSinceNow), repeats: false) { _ in
            MainActor.assumeIsolated { ReminderStore.shared.fireDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fireDue() {
        let now = Date()
        var changed = false
        for i in reminders.indices where !reminders[i].done && reminders[i].due <= now.addingTimeInterval(1) {
            fire(reminders[i])
            if let next = reminders[i].nextOccurrence(after: now, calendar: .current) {
                reminders[i].due = next
            } else {
                reminders[i].done = true
            }
            changed = true
        }
        if changed { save() }
        schedule()
    }

    private func fire(_ reminder: Reminder) {
        HUDModel.shared.show(.init(symbol: "bell.fill", label: String(reminder.text.prefix(16)), tint: Palette.gold), for: 8)
        PetModel.shared.send(.alert)
        ChatModel.shared.note(reminder.text, symbol: "bell.fill")
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = reminder.text
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(reminder.id)-\(Int(Date().timeIntervalSince1970))",
                                                                    content: content, trigger: nil))
    }

    private func requestNotificationsOnce() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: Self.url),
              let saved = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        // Finished one-offs are kept a week, then forgotten.
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        reminders = saved.filter { !$0.done || $0.due > cutoff }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(reminders).write(to: Self.url, options: .atomic)
    }

    static func dueLabel(_ reminder: Reminder) -> String {
        let time = reminder.due.formatted(date: .omitted, time: .shortened)
        if let repeats = reminder.repeats { return "\(repeats.label) at \(time)" }
        let cal = Calendar.current
        if cal.isDateInToday(reminder.due) { return "Today at \(time)" }
        if cal.isDateInTomorrow(reminder.due) { return "Tomorrow at \(time)" }
        return reminder.due.formatted(.dateTime.weekday(.wide).day().month().hour().minute())
    }
}
