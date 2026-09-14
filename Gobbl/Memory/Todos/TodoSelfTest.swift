#if DEBUG
import Foundation
import GobblCore

/// `--todo-selftest`: runs the to-do pipeline end to end on made-up captures
/// in a throwaway store (a chat request and a checkout left at payment), then
/// shows a confirmation page and checks the booking ticks itself off.
/// Uses one real /v1/extract call. Prints the result and quits.
@MainActor
enum TodoSelfTest {
    static func run() {
        Task { @MainActor in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-selftest-\(UUID().uuidString).sqlite")
            guard let store = try? MemoryStore(url: url) else {
                print("could not create a test store")
                exit(1)
            }
            MemoryModel.shared.useStoreForTesting(store)
            let now = Date()
            do {
                let chat = try store.beginSegment(appBundle: "net.whatsapp.WhatsApp", appName: "WhatsApp", window: "Samar Mustafa",
                                                  url: nil, chat: "Samar Mustafa", at: now.addingTimeInterval(-600))
                try store.addChunks(segment: chat, [
                    .init(ts: now.addingTimeInterval(-590), kind: "message", sender: "Samar Mustafa",
                          text: "Hey, can you send me the Q3 deck by Friday? Need it for the client call."),
                    .init(ts: now.addingTimeInterval(-580), kind: "message", fromMe: true, text: "Sure, I'll share it tomorrow morning"),
                ])
                let web = try store.beginSegment(appBundle: "com.google.Chrome", appName: "Google Chrome", window: "KSRTC - Review booking",
                                                 url: "https://ksrtc.in/oprs-web/booking", chat: nil, at: now.addingTimeInterval(-300))
                try store.addChunks(segment: web, [
                    .init(ts: now.addingTimeInterval(-290), kind: "text",
                          text: "Review your booking\nBengaluru to Mysuru, 20 Sep, 2 seats\nAmount to be Paid ₹1106\nPROCEED TO PAYMENT"),
                ])
                try store.setState("extractWatermark", String(now.addingTimeInterval(-3600).timeIntervalSince1970))

                await TodoCenter.shared.extract()
                print("== extracted")
                for t in TodoCenter.shared.open + TodoCenter.shared.maybe {
                    print("[\(t.status.rawValue) \(String(format: "%.2f", t.confidence))] \(t.title) | \(t.reason) | \(t.sourceApp) · \(t.chat ?? t.domain ?? "") | done when: \(t.doneSignal?.type ?? "-") \"\(t.doneSignal?.pattern ?? "")\"")
                }

                try store.addChunks(segment: web, [
                    .init(ts: Date().addingTimeInterval(1), kind: "text", text: "Payment successful. Booking confirmed. PNR K1234567"),
                ])
                TodoCenter.shared.checkResolution()
                print("== after the confirmation page")
                for t in (try? store.todos([.autoDone])) ?? [] { print("[auto_done] \(t.title)") }
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
