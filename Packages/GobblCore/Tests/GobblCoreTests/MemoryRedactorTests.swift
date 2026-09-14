import Testing
@testable import GobblCore

@Suite struct RedactorTests {
    @Test func cardsOnlyWhenLuhnValid() {
        #expect(Redactor.redact("card 4111 1111 1111 1111 exp 12/29") == "card [redacted:card] exp 12/29")
        #expect(Redactor.redact("order 4111-1111-1111-1112") == "order 4111-1111-1111-1112")
        #expect(Redactor.redact("tracking 1234567890123") == "tracking 1234567890123")
    }

    @Test func ibanOnlyWhenChecksumValid() {
        #expect(Redactor.redact("IBAN GB82 WEST 1234 5698 7654 32 thanks") == "IBAN [redacted:iban] thanks")
        #expect(Redactor.redact("ref GB00 WEST 1234 5698 7654 32") == "ref GB00 WEST 1234 5698 7654 32")
    }

    @Test func keysTokensAndPasswords() {
        #expect(Redactor.redact("key sk-or-v1-abcdefghijklmnopqrstuvwxyz0123") == "key [redacted:key]")
        #expect(Redactor.redact("AKIAABCDEFGHIJKLMNOP") == "[redacted:key]")
        #expect(Redactor.redact("ghp_" + String(repeating: "a", count: 36)) == "[redacted:key]")
        #expect(Redactor.redact("bearer eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.SflKxwRJSMeKKF2") == "bearer [redacted:token]")
        #expect(Redactor.redact("password: hunter2!") == "password: [redacted:password]")
    }

    @Test func oneTimeCodesAndCVV() {
        #expect(Redactor.redact("Your OTP is 482913. Do not share.") == "Your OTP is [redacted:otp]. Do not share.")
        #expect(Redactor.redact("verification code: 5521") == "verification code: [redacted:otp]")
        #expect(Redactor.redact("CVV 123") == "CVV [redacted:cvv]")
    }

    @Test func idsAndSSNs() {
        #expect(Redactor.redact("SSN 123-45-6789") == "SSN [redacted:ssn]")
        #expect(Redactor.redact("Aadhaar 2345 6789 0123") == "Aadhaar [redacted:id]")
    }

    @Test func leavesOrdinaryTextAlone() {
        let text = "Meet at 3:30 on 14 Sep 2026, room 204. Call +91 98765 43210 about the KSRTC booking for ₹1106."
        #expect(Redactor.redact(text) == text)
    }
}

@Suite struct LineDedupTests {
    @Test func onlyNewLinesPass() {
        var dedup = LineDedup()
        #expect(dedup.fresh(["Hello team", "  Build is green ", "x"]) == ["Hello team", "Build is green"])
        #expect(dedup.fresh(["hello   TEAM", "Ship Friday"]) == ["Ship Friday"])
    }

    @Test func forgetsOldestBeyondCapacity() {
        var dedup = LineDedup(capacity: 2)
        _ = dedup.fresh(["one", "two", "three"])
        #expect(dedup.fresh(["one"]) == ["one"])
        #expect(dedup.fresh(["three"]).isEmpty)
    }
}
