import Foundation

/// What the system's now-playing app reports.
public struct NowPlaying: Equatable, Sendable {
    public var bundleIdentifier: String?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var playing = false
    public var duration: TimeInterval?
    /// Elapsed time as of `timestamp`.
    public var elapsedTime: TimeInterval?
    public var timestamp: Date?
    public var playbackRate: Double?
    public var artworkData: Data?

    public init() {}

    public var hasMedia: Bool { !(title ?? "").isEmpty }

    /// Elapsed time extrapolated to `now` while playing, clamped to the duration.
    public func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        var value = elapsedTime
        if playing, let timestamp {
            let rate = playbackRate.flatMap { $0 > 0 ? $0 : nil } ?? 1
            value += max(0, now.timeIntervalSince(timestamp)) * rate
        }
        if let duration, duration > 0 { value = min(value, duration) }
        return max(0, value)
    }
}

/// Folds mediaremote-adapter `stream` output — one JSON object per line,
/// `{"type":"data","diff":Bool,"payload":{…}}` — into the current state.
/// A full payload replaces everything; a diff merges, and `null` removes a key.
public struct NowPlayingStream {
    private var fields: [String: Any] = [:]
    public private(set) var current = NowPlaying()

    public init() {}

    /// Returns true when the line changed the state.
    @discardableResult
    public mutating func apply(line: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return false }
        if (object["diff"] as? Bool ?? false) == false { fields = [:] }
        for (key, value) in payload {
            fields[key] = value is NSNull ? nil : value
        }
        let next = Self.decode(fields)
        guard next != current else { return false }
        current = next
        return true
    }

    private static let iso = ISO8601DateFormatter()

    static func decode(_ f: [String: Any]) -> NowPlaying {
        func text(_ key: String) -> String? { (f[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func number(_ key: String) -> Double? { (f[key] as? NSNumber)?.doubleValue }
        var n = NowPlaying()
        n.bundleIdentifier = text("bundleIdentifier")
        n.title = text("title")
        n.artist = text("artist")
        n.album = text("album")
        n.playing = f["playing"] as? Bool ?? false
        n.duration = number("duration")
        n.elapsedTime = number("elapsedTime")
        n.playbackRate = number("playbackRate")
        n.timestamp = text("timestamp").flatMap { iso.date(from: $0) }
        n.artworkData = text("artworkData").flatMap { Data(base64Encoded: $0) }
        return n
    }
}
