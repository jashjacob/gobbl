import Foundation

/// Masks secrets in captured screen text before it is stored: card numbers
/// (Luhn-checked), CVVs, IBANs (mod-97), SSNs, Aadhaar-style IDs, API keys,
/// JWTs, one-time codes and "password: …" pairs. Runs on every capture, so
/// it errs towards masking.
public enum Redactor {
    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var s = text
        s = replace(s, #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#) { _ in "[redacted:token]" }
        s = replace(s, keyPattern) { _ in "[redacted:key]" }
        s = replace(s, #"(?i)\b(password|passwd|pwd|passcode)(\s*[:=]\s*)\S+"#, template: "$1$2[redacted:password]")
        s = replace(s, #"(?i)(\b(?:cvv2?|cvc|security code)\b[^\d\n]{0,12})\d{3,4}\b"#, template: "$1[redacted:cvv]")
        s = replace(s, #"(?i)(\b(?:otp|code|verification code|passcode|pin)\b[^\d\n]{0,24})\d{4,8}\b"#, template: "$1[redacted:otp]")
        s = replace(s, #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]){11,30}\b"#) { isValidIBAN($0) ? "[redacted:iban]" : nil }
        s = replace(s, #"\b(?:\d[ -]?){12,18}\d\b"#) { luhn($0) ? "[redacted:card]" : nil }
        s = replace(s, #"\b\d{3}-\d{2}-\d{4}\b"#) { _ in "[redacted:ssn]" }
        // Aadhaar: 12 digits in threes of four, not part of a longer run (an IBAN, a card).
        s = replace(s, #"(?<!\d )(?<![A-Z]{4} )\b[2-9]\d{3} \d{4} \d{4}\b(?! ?[A-Z0-9]{2})"#) { _ in "[redacted:id]" }
        return s
    }

    private static let keyPattern = [
        #"\b(?:sk|pk|rk)[-_](?:live|test|or|ant|proj)[-_][A-Za-z0-9_-]{16,}"#, // Stripe, OpenRouter, Anthropic, OpenAI
        #"\bsk-[A-Za-z0-9]{32,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,                                          // AWS
        #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#,                                 // GitHub
        #"\bxox[abpr]-[A-Za-z0-9-]{10,}"#,                                  // Slack
        #"\bAIza[0-9A-Za-z_-]{35}\b"#,                                      // Google
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
    ].joined(separator: "|")

    static func luhn(_ candidate: String) -> Bool {
        let digits = candidate.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    static func isValidIBAN(_ candidate: String) -> Bool {
        let compact = candidate.replacingOccurrences(of: " ", with: "").uppercased()
        guard (15...34).contains(compact.count) else { return false }
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for ch in rearranged {
            let value: Int
            if let d = ch.wholeNumberValue { value = d } else if let a = ch.asciiValue, (65...90).contains(a) { value = Int(a) - 55 } else { return false }
            for digit in String(value) {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }

    private static func replace(_ s: String, _ pattern: String, template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Replaces each match with `transform(match)`, or leaves it when that returns nil.
    private static func replace(_ s: String, _ pattern: String, _ transform: (String) -> String?) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let match = ns.substring(with: m.range)
            guard let replacement = transform(match) else { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last)) + replacement
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
}

/// Remembers recently stored lines per window so a screen that barely
/// changes adds only its new lines. Bounded (LRU by insertion).
public struct LineDedup: Sendable {
    private var seen: Set<Int> = []
    private var order: [Int] = []
    private var head = 0
    public let capacity: Int

    public init(capacity: Int = 5000) {
        self.capacity = capacity
    }

    /// The lines not seen recently, in order; each is remembered from now on.
    public mutating func fresh(_ lines: [String]) -> [String] {
        var out: [String] = []
        for line in lines {
            let normal = Self.normalize(line)
            guard normal.count >= 2 else { continue }
            let key = normal.hashValue
            guard !seen.contains(key) else { continue }
            remember(key)
            out.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }

    static func normalize(_ line: String) -> String {
        line.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private mutating func remember(_ key: Int) {
        seen.insert(key)
        if order.count < capacity {
            order.append(key)
        } else {
            seen.remove(order[head])
            order[head] = key
            head = (head + 1) % capacity
        }
    }
}
