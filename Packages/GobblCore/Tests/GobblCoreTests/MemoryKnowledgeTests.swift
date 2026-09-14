import Foundation
import Testing
@testable import GobblCore

@Suite struct EntityRulesTests {
    @Test func normalizing() {
        #expect(EntityRules.normalize("  Nishánth  R. ") == "nishanth r")
        #expect(EntityRules.isNoise("You"))
        #expect(EntityRules.isNoise("12345"))
        #expect(!EntityRules.isNoise("Samar"))
    }

    @Test func sameOrNot() {
        #expect(EntityRules.mightBeSame("Samar", "Samar Mustafa") != nil)
        #expect(EntityRules.mightBeSame("S Mustafa", "Samar Mustafa") != nil)
        #expect(EntityRules.mightBeSame("Samar Mustafa", "Samar Mustafa") == nil)
        #expect(EntityRules.mightBeSame("Sam", "Samar Mustafa") == nil)
        #expect(EntityRules.mightBeSame("Al", "Al Pacino") == nil) // too short to guess
        #expect(EntityRules.mightBeSame("Pritesh Kumar", "Priya Kumar") == nil)
    }
}

@Suite struct KnowledgeStoreTests {
    private func store() throws -> MemoryStore {
        try MemoryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-kb-\(UUID().uuidString).sqlite"))
    }

    @Test func hardIdentifiersMergeNamesOnlySuggest() throws {
        let db = try store()
        let t = Date()
        let a = try db.upsertEntity(type: .person, name: "Samar", identifiers: [("email", "samar@acme.com")], at: t)
        let b = try db.upsertEntity(type: .person, name: "Samar Mustafa", identifiers: [("email", "SAMAR@acme.com")], role: "Designer", at: t)
        #expect(a == b) // same email → same person, fuller name wins
        let detail = try #require(try db.entityDetail(a!))
        #expect(detail.summary.name == "Samar Mustafa")
        #expect(detail.summary.role == "Designer")

        let c = try db.upsertEntity(type: .person, name: "Pritesh", at: t)
        let d = try db.upsertEntity(type: .person, name: "Pritesh Kumar", at: t)
        #expect(c != d)
        let suggestions = try db.mergeSuggestions()
        #expect(suggestions.count == 1)
        #expect(Set([suggestions[0].a.name, suggestions[0].b.name]) == ["Pritesh", "Pritesh Kumar"])
        #expect(try db.upsertEntity(type: .person, name: "Everyone", at: t) == nil)
    }

    @Test func mergeAndUndo() throws {
        let db = try store()
        let t = Date()
        let seg = try db.beginSegment(appBundle: "net.whatsapp.WhatsApp", appName: "WhatsApp", window: "Pritesh", url: nil, chat: "Pritesh", at: t)
        try db.addChunks(segment: seg, [.init(ts: t, kind: "message", sender: "Pritesh", text: "video is truncated"),
                                        .init(ts: t, kind: "message", sender: "Pritesh Kumar", text: "re-exporting now")])
        let chunks = try db.chunks(since: t.addingTimeInterval(-1))
        let short = try #require(try db.upsertEntity(type: .person, name: "Pritesh", at: t))
        let full = try #require(try db.upsertEntity(type: .person, name: "Pritesh Kumar", at: t))
        try db.addMention(entity: short, chunk: chunks[0].chunkID, role: "sender", at: t, app: "WhatsApp")
        try db.addMention(entity: full, chunk: chunks[1].chunkID, role: "sender", at: t, app: "WhatsApp")

        let log = try db.merge(keep: full, remove: short)
        #expect(try db.entityDetail(full)?.recent.count == 2)
        #expect(try db.entityDetail(short) == nil)
        #expect(try db.mergeSuggestions().isEmpty)
        #expect(try db.findEntity(named: "pritesh")?.id == full)

        try db.undoMerge(log)
        #expect(try db.entityDetail(short)?.recent.count == 1)
        #expect(try db.entityDetail(full)?.recent.count == 1)
        #expect(try db.mergeSuggestions().isEmpty) // undone = "not the same"
    }

    @Test func forgottenPeopleStayForgotten() throws {
        let db = try store()
        let t = Date()
        let id = try #require(try db.upsertEntity(type: .person, name: "Rahul Verma", role: "Recruiter", at: t))
        try db.forgetEntity(id)
        #expect(try db.upsertEntity(type: .person, name: "Rahul Verma", at: t) == nil)
        #expect(try db.entities(.person, everyone: true).isEmpty)
    }

    @Test func relationsFactsAndSearch() throws {
        let db = try store()
        let t = Date()
        let person = try #require(try db.upsertEntity(type: .person, name: "Anita Ratnam", at: t))
        let org = try #require(try db.upsertEntity(type: .org, name: "Toss the Coin", at: t))
        try db.addRelation(person, org, kind: "works_at", evidence: nil)
        try db.addRelation(person, org, kind: "works_at", evidence: nil)
        try db.addFact(entity: person, key: "prefers", value: "email over calls", evidence: nil, confidence: 0.8)
        let detail = try #require(try db.entityDetail(person))
        #expect(detail.related.first?.entity.name == "Toss the Coin")
        #expect(detail.facts.first?.value == "email over calls")
        #expect(try db.entities(.person, matching: "anita").map(\.name) == ["Anita Ratnam"])
        #expect(try db.findEntity(named: "Anita")?.id == person)
    }
}
