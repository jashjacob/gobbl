import Foundation
import Testing
@testable import GobblCore

@Suite struct CaptureRulesTests {
    @Test func kinds() {
        #expect(CaptureRules.kind(of: "net.whatsapp.WhatsApp") == .messaging)
        #expect(CaptureRules.kind(of: "com.google.Chrome") == .browser)
        #expect(CaptureRules.kind(of: "com.jetbrains.intellij") == .code)
        #expect(CaptureRules.kind(of: "com.apple.Notes") == .generic)
        #expect(CaptureRules.deniedApps.contains("com.1password.1password"))
    }

    @Test func privateWindowsAndDomains() {
        #expect(CaptureRules.isPrivateWindow(title: "New Incognito Tab - Google Chrome"))
        #expect(CaptureRules.isPrivateWindow(title: "Private Browsing"))
        #expect(!CaptureRules.isPrivateWindow(title: "Inbox - Gmail"))
        #expect(CaptureRules.isDeniedDomain("netbanking.hdfcbank.com"))
        #expect(CaptureRules.isDeniedDomain("kite.zerodha.com"))
        #expect(!CaptureRules.isDeniedDomain("ksrtc.in"))
        #expect(CaptureRules.isDeniedDomain("mail.example.com", extra: ["example.com"]))
        #expect(CaptureRules.domain(of: "https://www.wanderlog.com/trip/1") == "wanderlog.com")
    }
}

@Suite struct ScreenParserTests {
    @Test func genericLinesSkipSecureAndDuplicates() {
        let nodes = [
            AXNode(role: "AXHeading", text: "Scoring check"),
            AXNode(role: "AXStaticText", text: "Scoring check"),
            AXNode(role: "AXTextField", subrole: "AXSecureTextField", text: "hunter2"),
            AXNode(role: "AXStaticText", text: "Ignore commas\nFix proper nouns"),
            AXNode(role: "AXButton", text: "Save"),
        ]
        #expect(GenericParser.lines(nodes) == ["Scoring check", "Ignore commas", "Fix proper nouns"])
    }

    @Test func slackStyleHeadersAndSelf() {
        // Slack: "Name" then a time above each run; everyone is left-aligned.
        let nodes = [
            AXNode(role: "AXStaticText", text: "Samar Mustafa"),
            AXNode(role: "AXStaticText", text: "10:42 AM"),
            AXNode(role: "AXStaticText", text: "can you send the deck by Friday?"),
            AXNode(role: "AXStaticText", text: "Kevin John"),
            AXNode(role: "AXStaticText", text: "10:44 AM"),
            AXNode(role: "AXStaticText", text: "Sure, I'll share it tomorrow"),
        ]
        let messages = MessagingParser.messages(nodes, me: ["Kevin John"])
        #expect(messages == [
            ChatMessage(sender: "Samar Mustafa", text: "can you send the deck by Friday?", fromMe: false),
            ChatMessage(sender: nil, text: "Sure, I'll share it tomorrow", fromMe: true),
        ])
    }

    @Test func whatsappStyleBubblesAndStatus() {
        // WhatsApp/iMessage: own bubbles on the right, "Read" under them.
        let nodes = [
            AXNode(role: "AXStaticText", text: "Are we still on for 6?", x: 0.05, width: 0.4),
            AXNode(role: "AXStaticText", text: "6:02 PM", x: 0.3, width: 0.1),
            AXNode(role: "AXStaticText", text: "Yes, see you there", x: 0.55, width: 0.35),
            AXNode(role: "AXStaticText", text: "Read", x: 0.8, width: 0.1),
        ]
        let messages = MessagingParser.messages(nodes)
        #expect(messages.count == 2)
        #expect(messages[0].fromMe == false)
        #expect(messages[1] == ChatMessage(sender: nil, text: "Yes, see you there", fromMe: true))
    }

    @Test func sidebarPreviewsAreNotMessages() {
        // Messages/Telegram: the chat list sits on the left; the conversation to its right.
        let nodes = [
            AXNode(role: "AXStaticText", text: "Anita Ratnam, Active, 3:55 PM", x: 0.01, width: 0.18),
            AXNode(role: "AXStaticText", text: "See you at the venue", x: 0.35, width: 0.3),
        ]
        #expect(MessagingParser.messages(nodes).map(\.text) == ["See you at the venue"])
    }

    @Test func namesAreNotMistakenForMessages() {
        #expect(MessagingParser.looksLikeName("Samar Mustafa"))
        #expect(MessagingParser.looksLikeName("निशांत"))
        #expect(!MessagingParser.looksLikeName("Sounds good to me."))
        #expect(!MessagingParser.looksLikeName("Sounds good"))
        #expect(!MessagingParser.looksLikeName("Meet at 5"))
    }

    @Test func chatNameFromWindowTitle() {
        #expect(MessagingParser.chatName(windowTitle: "general (Channel) - Acme - Slack", appName: "Slack") == "general (Channel)")
        #expect(MessagingParser.chatName(windowTitle: "WhatsApp", appName: "WhatsApp") == nil)
        #expect(MessagingParser.chatName(windowTitle: "Pritesh Kumar — Telegram", appName: "Telegram") == "Pritesh Kumar")
    }
}

@Suite struct MemoryStoreTests {
    private func store() throws -> MemoryStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-test-\(UUID().uuidString).sqlite")
        return try MemoryStore(url: url)
    }

    @Test func storesSearchesAndForgets() throws {
        let db = try store()
        let now = Date()
        let seg = try db.beginSegment(appBundle: "net.whatsapp.WhatsApp", appName: "WhatsApp", window: "Samar",
                                      url: nil, chat: "Samar", at: now.addingTimeInterval(-60))
        try db.addChunks(segment: seg, [
            .init(ts: now.addingTimeInterval(-50), kind: "message", sender: "Samar", text: "Can you complete the KSRTC booking?"),
            .init(ts: now.addingTimeInterval(-40), kind: "message", fromMe: true, text: "Sure, doing it tonight"),
        ])
        let web = try db.beginSegment(appBundle: "com.google.Chrome", appName: "Chrome", window: "KSRTC",
                                      url: "https://www.ksrtc.in/booking", chat: nil, at: now)
        try db.addChunks(segment: web, [.init(ts: now, kind: "text", text: "Amount to be paid ₹1106. Proceed to payment")])

        let hits = try db.search("ksrtc booking")
        #expect(hits.count == 1)
        #expect(hits[0].sender == "Samar")
        #expect(hits[0].snippet.contains("[KSRTC]") || hits[0].snippet.lowercased().contains("[ksrtc]"))
        #expect(try db.search("payment").first?.domain == "ksrtc.in")
        #expect(try db.search("tonig").first?.fromMe == true) // prefix match
        #expect(try db.search("\"; DROP TABLE chunks; --").isEmpty)

        #expect(try db.stats().chunks == 3)
        try db.forget(from: now.addingTimeInterval(-45))
        #expect(try db.stats().chunks == 1)
        #expect(try db.search("payment").isEmpty)
        try db.forgetAll()
        #expect(try db.stats() .chunks == 0)
    }

    @Test func chunksSinceAreOldestFirst() throws {
        let db = try store()
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let seg = try db.beginSegment(appBundle: "com.apple.Notes", appName: "Notes", window: "n", url: nil, chat: nil, at: t)
        try db.addChunks(segment: seg, [.init(ts: t.addingTimeInterval(20), kind: "text", text: "second"),
                                        .init(ts: t.addingTimeInterval(10), kind: "text", text: "first")])
        #expect(try db.chunks(since: t).map(\.snippet) == ["first", "second"])
    }
}
