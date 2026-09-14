import Foundation

/// A JSON value that keeps key order and the exact text of strings and
/// numbers, so editing one entry in someone's config file leaves the rest
/// of it as they wrote it. Whitespace is re-indented using the file's own
/// indent.
public indirect enum OrderedJSON: Equatable, Sendable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    /// Raw source text: a quoted string, a number, true, false or null.
    case scalar(String)

    public enum ParseError: Error, Equatable {
        /// Comments or trailing commas (JSONC): Gobbl won't rewrite these files.
        case jsonc
        case invalid
    }

    public static func == (a: OrderedJSON, b: OrderedJSON) -> Bool {
        switch (a, b) {
        case let (.object(x), .object(y)): x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(x), .array(y)): x == y
        case let (.scalar(x), .scalar(y)): x == y
        default: false
        }
    }

    // MARK: Building

    public static func string(_ s: String) -> OrderedJSON {
        let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data("\"\"".utf8)
        return .scalar(String(decoding: data, as: UTF8.self))
    }

    /// The decoded value of a string scalar.
    public var stringValue: String? {
        guard case .scalar(let raw) = self, raw.hasPrefix("\"") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed) as? String
    }

    public var members: [(key: String, value: OrderedJSON)]? {
        if case .object(let m) = self { return m }
        return nil
    }

    public subscript(key: String) -> OrderedJSON? {
        members?.first { $0.key == key }?.value
    }

    /// Replaces the value in place, or appends the key at the end.
    public mutating func set(_ key: String, _ value: OrderedJSON?) {
        guard case .object(var m) = self else { return }
        if let i = m.firstIndex(where: { $0.key == key }) {
            if let value { m[i].value = value } else { m.remove(at: i) }
        } else if let value {
            m.append((key, value))
        }
        self = .object(m)
    }

    // MARK: Parsing

    public static func parse(_ text: String) throws -> OrderedJSON {
        var p = Parser(Array(text.utf8))
        p.skip()
        let value = try p.value()
        p.skip()
        guard p.i == p.b.count else { throw p.extra() }
        return value
    }

    private struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        mutating func skip() {
            while i < b.count, [0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
        }

        /// What an unexpected character means: a comment is JSONC, anything else is broken.
        func extra() -> ParseError {
            i < b.count && b[i] == UInt8(ascii: "/") ? .jsonc : .invalid
        }

        mutating func value() throws -> OrderedJSON {
            guard i < b.count else { throw ParseError.invalid }
            switch b[i] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .scalar(try string())
            case UInt8(ascii: "/"): throw ParseError.jsonc
            default: return .scalar(try literal())
            }
        }

        mutating func object() throws -> OrderedJSON {
            i += 1
            var m: [(key: String, value: OrderedJSON)] = []
            skip()
            if i < b.count, b[i] == UInt8(ascii: "}") { i += 1; return .object(m) }
            while true {
                skip()
                guard i < b.count else { throw ParseError.invalid }
                if b[i] == UInt8(ascii: "}") { throw ParseError.jsonc }  // trailing comma
                guard b[i] == UInt8(ascii: "\"") else { throw extra() }
                let rawKey = try string()
                guard let key = try? JSONSerialization.jsonObject(with: Data(rawKey.utf8), options: .fragmentsAllowed) as? String else {
                    throw ParseError.invalid
                }
                skip()
                guard i < b.count, b[i] == UInt8(ascii: ":") else { throw extra() }
                i += 1
                skip()
                m.append((key, try value()))
                skip()
                guard i < b.count else { throw ParseError.invalid }
                if b[i] == UInt8(ascii: ",") { i += 1; continue }
                if b[i] == UInt8(ascii: "}") { i += 1; return .object(m) }
                throw extra()
            }
        }

        mutating func array() throws -> OrderedJSON {
            i += 1
            var a: [OrderedJSON] = []
            skip()
            if i < b.count, b[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
            while true {
                skip()
                guard i < b.count else { throw ParseError.invalid }
                if b[i] == UInt8(ascii: "]") { throw ParseError.jsonc }
                a.append(try value())
                skip()
                guard i < b.count else { throw ParseError.invalid }
                if b[i] == UInt8(ascii: ",") { i += 1; continue }
                if b[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
                throw extra()
            }
        }

        mutating func string() throws -> String {
            let start = i
            i += 1
            while i < b.count {
                if b[i] == UInt8(ascii: "\\") { i += 2; continue }
                if b[i] == UInt8(ascii: "\"") {
                    i += 1
                    return String(decoding: b[start..<i], as: UTF8.self)
                }
                i += 1
            }
            throw ParseError.invalid
        }

        mutating func literal() throws -> String {
            let start = i
            while i < b.count, !([0x20, 0x09, 0x0A, 0x0D] + Array(",]}/".utf8)).contains(b[i]) { i += 1 }
            let raw = String(decoding: b[start..<i], as: UTF8.self)
            guard raw == "true" || raw == "false" || raw == "null" || Double(raw) != nil else { throw ParseError.invalid }
            return raw
        }
    }

    // MARK: Writing

    /// Pretty-printed like `JSON.stringify(v, null, indent)`.
    public func serialized(indent: String = "  ") -> String {
        var out = ""
        write(into: &out, level: 0, indent: indent)
        return out
    }

    private func write(into out: inout String, level: Int, indent: String) {
        let pad = String(repeating: indent, count: level)
        switch self {
        case .scalar(let raw):
            out += raw
        case .array(let a):
            guard !a.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (n, v) in a.enumerated() {
                out += pad + indent
                v.write(into: &out, level: level + 1, indent: indent)
                out += n == a.count - 1 ? "\n" : ",\n"
            }
            out += pad + "]"
        case .object(let m):
            guard !m.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (n, member) in m.enumerated() {
                out += pad + indent + OrderedJSON.string(member.key).serialized() + ": "
                member.value.write(into: &out, level: level + 1, indent: indent)
                out += n == m.count - 1 ? "\n" : ",\n"
            }
            out += pad + "}"
        }
    }

    /// The indent a file already uses (two spaces if it can't tell).
    public static func detectIndent(_ text: String) -> String {
        for line in text.split(separator: "\n").dropFirst() {
            let lead = line.prefix { $0 == " " || $0 == "\t" }
            if !lead.isEmpty { return String(lead) }
        }
        return "  "
    }
}
