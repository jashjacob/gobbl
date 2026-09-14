import Foundation

public struct LyricLine: Equatable, Sendable {
    public var time: TimeInterval
    public var text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

/// Synced lyrics in LRC format ("[01:23.45] line"), as served by lrclib.net.
public enum LRC {
    public static func parse(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var stamps: [TimeInterval] = []
            // A line can carry several timestamps: "[00:10.00][01:10.00] chorus".
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    stamps.append(m * 60 + s)
                }
                rest = rest[rest.index(after: close)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            for t in stamps { lines.append(LyricLine(time: t, text: words)) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// The line being sung at `time` (nil before the first line or on an empty instrumental line).
    public static func line(at time: TimeInterval, in lines: [LyricLine]) -> LyricLine? {
        guard let line = lines.last(where: { $0.time <= time }), !line.text.isEmpty else { return nil }
        return line
    }
}
