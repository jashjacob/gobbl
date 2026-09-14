#if DEBUG
import Foundation
import GobblCore

/// `--digest-selftest`: writes a digest for a made-up day in a throwaway store
/// (trip planning in the morning, a chat in the afternoon, mail in the
/// evening) with one real /v1/digest call, prints it and quits.
@MainActor
enum DigestSelfTest {
    static func run() {
        Task { @MainActor in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-digest-\(UUID().uuidString).sqlite")
            guard let store = try? MemoryStore(url: url) else {
                print("could not create a test store")
                exit(1)
            }
            MemoryModel.shared.useStoreForTesting(store)
            let cal = Calendar.current
            let day = DayParts.dayKey(Date().addingTimeInterval(-86400), calendar: cal)
            guard let start = DayParts.range(of: day, calendar: cal)?.start else { exit(1) }
            func at(_ hour: Double) -> Date { start.addingTimeInterval((hour - 5) * 3600) }
            do {
                let trip = try store.beginSegment(appBundle: "com.google.Chrome", appName: "Google Chrome", window: "Wanderlog - UK & Ireland 2026",
                                                  url: "https://wanderlog.com/plan/uk", chat: nil, at: at(9))
                try store.addChunks(segment: trip, [
                    .init(ts: at(9.1), kind: "text", text: "Day 3 Edinburgh: castle, Royal Mile. Train to York 10:04, £42"),
                    .init(ts: at(10.4), kind: "text", text: "Dublin hotels shortlist: The Hendrick, Wynn's. Car-free route via ferry"),
                ])
                let chat = try store.beginSegment(appBundle: "net.whatsapp.WhatsApp", appName: "WhatsApp", window: "WhatsApp",
                                                  url: nil, chat: "Samar Mustafa", at: at(14))
                try store.addChunks(segment: chat, [
                    .init(ts: at(14.2), kind: "message", sender: "Samar Mustafa", text: "Can you send the Q3 deck by Friday?"),
                    .init(ts: at(14.6), kind: "message", fromMe: true, text: "Yes, finishing the revenue slides now"),
                ])
                let mail = try store.beginSegment(appBundle: "com.readdle.smartemail-Mac", appName: "Spark", window: "Inbox",
                                                  url: nil, chat: nil, at: at(19))
                try store.addChunks(segment: mail, [
                    .init(ts: at(19.5), kind: "mail", text: "Re: SMTP cutover - test sends worked, ready once DNS points to the new IPs"),
                ])
                await DigestCenter.shared.build(day: day)
                print("== digest for \(day)")
                for d in DigestCenter.shared.digests where d.day == day {
                    print("[\(d.part)] apps: \(d.apps.joined(separator: ", "))")
                    for b in d.bullets { print("  - \(b)") }
                }
                print("== brief text\n\(DigestCenter.shared.text(forDay: day) ?? "(none)")")
            } catch {
                print("test store error: \(error)")
            }
            if let e = AIClient.shared.lastError { print("lastError: \(e)") }
            try? FileManager.default.removeItem(at: url)
            fflush(stdout)
            exit(0)
        }
    }
}
#endif
