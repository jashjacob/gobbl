import CryptoKit
import Foundation
import Testing
@testable import GobblCore

@Suite struct GobblKeyMachineTests {
    /// Feeds events and collects the actions, ticking every 10 ms in between.
    private func run(_ events: [GobblKeyEvent], until end: TimeInterval = 2) -> [GobblKeyAction] {
        var m = GobblKeyMachine()
        var out: [GobblKeyAction] = []
        var t: TimeInterval = 0
        var queue = events
        while t <= end {
            while let next = queue.first, time(of: next) <= t {
                queue.removeFirst()
                if let a = m.handle(next) { out.append(a) }
            }
            if let a = m.handle(.tick(t)) { out.append(a) }
            t += 0.01
        }
        return out
    }

    private func time(of e: GobblKeyEvent) -> TimeInterval {
        switch e {
        case .down(let t), .up(let t), .otherKey(let t), .tick(let t): t
        }
    }

    @Test func tapFiresAfterTheDoubleTapWindow() {
        #expect(run([.down(0), .up(0.08)]) == [.tap])
    }

    @Test func doubleTap() {
        #expect(run([.down(0), .up(0.08), .down(0.2), .up(0.28)]) == [.doubleTap])
    }

    @Test func holdStartsAndEnds() {
        #expect(run([.down(0), .up(1.0)]) == [.holdBegan(locked: false), .holdEnded])
    }

    @Test func doubleTapAndHoldLocks() {
        #expect(run([.down(0), .up(0.08), .down(0.2), .up(1.2)]) == [.holdBegan(locked: true), .holdEnded])
    }

    @Test func optionAsAModifierCancels() {
        // ⌥E: another key while ⌥ is down.
        #expect(run([.down(0), .otherKey(0.05), .up(0.1)]) == [.cancelled])
    }

    @Test func lateSecondPressIsATapThenANewPress() {
        #expect(run([.down(0), .up(0.05), .down(0.6), .up(0.65)]) == [.tap, .tap])
    }
}

@Suite struct AIProtocolTests {
    @Test func canonicalStringAndSignatureVerify() throws {
        let body = Data(#"{"a":1}"#.utf8)
        let canonical = RequestSigning.canonical(method: "post", path: "/v1/write", timestamp: 1_700_000_000, body: body)
        #expect(canonical == "POST\n/v1/write\n1700000000\n015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862")
        let key = Curve25519.Signing.PrivateKey()
        let signature = try RequestSigning.sign(key, method: "POST", path: "/v1/write", timestamp: 1_700_000_000, body: body)
        let raw = try #require(Data(base64Encoded: signature))
        #expect(key.publicKey.isValidSignature(raw, for: Data(canonical.utf8)))
        #expect(!Curve25519.Signing.PrivateKey().publicKey.isValidSignature(raw, for: Data(canonical.utf8)))
    }

    /// The worked example in server/ai-worker/API.md. CryptoKit randomises
    /// Ed25519 signatures (still standard, still verifiable), so instead of
    /// matching bytes: same key, same canonical string, and each side's
    /// signature verifies against the other.
    @Test func compatibleWithTheWorkersSigningVectors() throws {
        let seed = Data((1...32).map { UInt8($0) })
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        #expect(key.publicKey.rawRepresentation.base64EncodedString() == "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=")
        let body = Data(#"{"transcript":"um so I think we should uh ship it friday","style":"light","app":"Slack","locale":"en-US"}"#.utf8)
        let canonical = RequestSigning.canonical(method: "POST", path: "/v1/cleanup", timestamp: 1_789_430_400, body: body)
        #expect(canonical == "POST\n/v1/cleanup\n1789430400\n992d23a73ff9f269724343d89c38532f5ff6474d41f2fa8fcba3f4f7d4af6926")
        let workers = try #require(Data(base64Encoded: "pP5W4jFxbSaI9+hfeQsw3dkxGgoIOI6U7FbdAZmlXO81J2fVz+rYdvZCY0wiGr8n3p5vN+8b/r3kWw2e14qdBQ=="))
        #expect(key.publicKey.isValidSignature(workers, for: Data(canonical.utf8)))
        let ours = try #require(Data(base64Encoded: try RequestSigning.sign(key, method: "POST", path: "/v1/cleanup",
                                                                             timestamp: 1_789_430_400, body: body)))
        #expect(key.publicKey.isValidSignature(ours, for: Data(canonical.utf8)))
        let quota = RequestSigning.canonical(method: "GET", path: "/v1/quota", timestamp: 1_789_430_400, body: Data())
        let workersQuota = try #require(Data(base64Encoded: "qyASmwkW2hH9ZhqDmDbLhJ4Grq+cFUijogFskGtSNt6De2C9Xnz2HK22+FtRRftGSiAN85v22H/HmoJ5G4+WAQ=="))
        #expect(key.publicKey.isValidSignature(workersQuota, for: Data(quota.utf8)))
    }

    @Test func sseParsesSplitChunksCommentsAndMultilineData() {
        var p = SSEParser()
        var events = p.feed(": keep-alive\n\nevent: delta\ndata: {\"text\":\"Hel")
        #expect(events.isEmpty)
        events = p.feed("lo\"}\n\nevent: done\r\ndata: {}\r\n\r\n")
        #expect(events == [SSEEvent(event: "delta", data: #"{"text":"Hello"}"#), SSEEvent(event: "done", data: "{}")])
        events = p.feed("data: a\ndata: b\n\n")
        #expect(events == [SSEEvent(event: "message", data: "a\nb")])
    }

    @Test func writeModeFromTheField() {
        #expect(WriteMode.for(FieldSnapshot(value: "hello there", selection: "there")) == .rewrite)
        #expect(WriteMode.for(FieldSnapshot(value: "  /g what's the capital of Peru")) == .answer)
        #expect(WriteMode.for(FieldSnapshot(value: "say yes but next week")) == .instruction)
        #expect(WriteMode.for(FieldSnapshot(value: "  \n")) == .draft)
        #expect(WriteMode.answer.text(from: FieldSnapshot(value: "/g  capital of Peru")) == "capital of Peru")
        #expect(WriteMode.instruction.replacesWholeField)
        #expect(!WriteMode.rewrite.replacesWholeField)
    }
}
