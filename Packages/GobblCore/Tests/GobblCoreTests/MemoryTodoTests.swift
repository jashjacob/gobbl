import Foundation
import Testing
@testable import GobblCore

@Suite struct TodoRulesTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func todo(_ title: String, people: [String] = [], domain: String? = nil, chat: String? = nil,
                      signal: MemoryTodo.DoneSignal? = nil, status: MemoryTodo.Status = .suggested) -> MemoryTodo {
        MemoryTodo(title: title, reason: "", status: status, confidence: 0.9, sourceApp: "Chrome", window: "w",
                   chat: chat, domain: domain, people: people, firstSeen: t0, doneSignal: signal)
    }

    @Test func confidenceTiersFollowSensitivity() {
        #expect(TodoRules.initialStatus(confidence: 0.85) == .suggested)
        #expect(TodoRules.initialStatus(confidence: 0.6) == .maybe)
        #expect(TodoRules.initialStatus(confidence: 0.4) == nil)
        #expect(TodoRules.initialStatus(confidence: 0.85, sensitivity: .conservative) == .maybe)
        #expect(TodoRules.initialStatus(confidence: 0.72, sensitivity: .eager) == .suggested)
    }

    @Test func duplicates() {
        let a = todo("Complete KSRTC booking", domain: "ksrtc.in")
        #expect(TodoRules.isDuplicate(todo("Complete the KSRTC booking"), of: a))
        #expect(TodoRules.isDuplicate(todo("Finish KSRTC booking payment", domain: "ksrtc.in"), of: a))
        #expect(!TodoRules.isDuplicate(todo("Fix Yale Bluetooth integration"), of: a))
        #expect(TodoRules.isDuplicate(todo("Send deck", people: ["Samar"]), of: todo("Send the Q3 deck", people: ["Samar"])))
    }

    @Test func pageConfirmationResolvesOnTheSameSite() {
        let t = todo("Complete KSRTC booking", domain: "ksrtc.in",
                     signal: .init(type: "page_contains", pattern: "booking confirmed|payment successful"))
        #expect(TodoRules.resolves(t, .init(text: "Payment successful. PNR 12345", domain: "ksrtc.in", chat: nil, fromMe: false, kind: "text")))
        #expect(!TodoRules.resolves(t, .init(text: "Payment successful", domain: "amazon.in", chat: nil, fromMe: false, kind: "text")))
        #expect(!TodoRules.resolves(t, .init(text: "Proceed to payment", domain: "ksrtc.in", chat: nil, fromMe: false, kind: "text")))
    }

    @Test func replyResolvesInTheSameChat() {
        let t = todo("Reply to Samar about the deck", people: ["Samar"], chat: "Samar Mustafa",
                     signal: .init(type: "reply_to", pattern: ""))
        #expect(TodoRules.resolves(t, .init(text: "Sending it now", domain: nil, chat: "Samar Mustafa", fromMe: true, kind: "message")))
        #expect(!TodoRules.resolves(t, .init(text: "ok", domain: nil, chat: "Samar Mustafa", fromMe: false, kind: "message")))
        #expect(!TodoRules.resolves(t, .init(text: "hi", domain: nil, chat: "Family", fromMe: true, kind: "message")))
    }

    @Test func fileSentAndClosedItemsNeverResolve() {
        let t = todo("Send the invoice", chat: "Acme", signal: .init(type: "file_sent", pattern: "invoice"))
        #expect(TodoRules.resolves(t, .init(text: "Invoice-Sept.pdf", domain: nil, chat: "Acme", fromMe: true, kind: "message")))
        var done = t
        done.status = .done
        #expect(!TodoRules.resolves(done, .init(text: "Invoice-Sept.pdf", domain: nil, chat: "Acme", fromMe: true, kind: "message")))
        #expect(!TodoRules.resolves(todo("x", signal: .init(type: "none", pattern: "")),
                                    .init(text: "x", domain: nil, chat: nil, fromMe: true, kind: "text")))
    }

    @Test func staleAfterAQuietWeekUnlessDueAhead() {
        let t = todo("Book tickets")
        #expect(!TodoRules.isStale(t, now: t0.addingTimeInterval(3 * 86400)))
        #expect(TodoRules.isStale(t, now: t0.addingTimeInterval(8 * 86400)))
        var due = t
        due.due = t0.addingTimeInterval(20 * 86400)
        #expect(!TodoRules.isStale(due, now: t0.addingTimeInterval(8 * 86400)))
    }

    @Test func sortingPutsDueFirst() {
        var a = todo("a"); a.confidence = 0.95
        var b = todo("b"); b.due = t0
        var c = todo("c", status: .confirmed); c.confidence = 0.5
        #expect(TodoRules.sorted([a, b, c]).map(\.title) == ["b", "c", "a"])
    }
}

@Suite struct ExtractionFilterTests {
    @Test func whatGoesToTheAI() {
        #expect(ExtractionFilter.isCandidate(appKind: .messaging, domain: nil, text: "lol"))
        #expect(ExtractionFilter.isCandidate(appKind: .browser, domain: "ksrtc.in", text: "Amount to be paid ₹1106"))
        #expect(!ExtractionFilter.isCandidate(appKind: .browser, domain: "news.ycombinator.com", text: "please read"))
        #expect(!ExtractionFilter.isCandidate(appKind: .browser, domain: "wikipedia.org", text: "The river flows north"))
        #expect(ExtractionFilter.isCandidate(appKind: .generic, domain: nil, text: "Don't forget to call the bank by Friday"))
        #expect(!ExtractionFilter.isCandidate(appKind: .code, domain: nil, text: "func main() {}"))
        #expect(ExtractionFilter.isCandidate(appKind: .code, domain: nil, text: "// TODO: handle retries"))
    }
}

@Suite struct MemoryStoreTodoTests {
    @Test func todosRoundTripWithEvidence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-todo-\(UUID().uuidString).sqlite")
        let db = try MemoryStore(url: url)
        let now = Date()
        let seg = try db.beginSegment(appBundle: "com.google.Chrome", appName: "Chrome", window: "KSRTC", url: "https://ksrtc.in", chat: nil, at: now)
        try db.addChunks(segment: seg, [.init(ts: now, kind: "text", text: "Proceed to payment")])
        let chunk = try db.chunks(since: now.addingTimeInterval(-1)).first!
        #expect(chunk.appBundle == "com.google.Chrome")

        var todo = MemoryTodo(title: "Complete KSRTC booking", reason: "Left at payment", status: .suggested, confidence: 0.9,
                              sourceApp: "Chrome", window: "KSRTC", domain: "ksrtc.in", firstSeen: now,
                              doneSignal: .init(type: "page_contains", pattern: "payment successful"))
        todo.id = try db.insertTodo(todo, evidence: [chunk.chunkID])
        var open = try db.todos([.suggested, .confirmed])
        #expect(open.map(\.title) == ["Complete KSRTC booking"])
        #expect(open[0].doneSignal?.type == "page_contains")
        #expect(try db.evidence(todo: todo.id).first?.snippet == "Proceed to payment")

        open[0].status = .autoDone
        open[0].previousStatus = .suggested
        try db.updateTodo(open[0])
        #expect(try db.todos([.suggested]).isEmpty)
        #expect(try db.todos([.autoDone]).first?.previousStatus == .suggested)

        try db.setState("extractWatermark", "123")
        #expect(db.state("extractWatermark") == "123")
    }
}
