import Foundation
import GobblCore
import Observation

/// Synced lyrics for the current track from lrclib.net (free, no key). Off by
/// default because it sends the track's title and artist to a third party.
@MainActor @Observable
final class LyricsModel {
    static let shared = LyricsModel()

    private(set) var lines: [LyricLine] = []
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    var enabled: Bool { UserDefaults.standard.bool(forKey: "lyricsEnabled") }

    func line(at time: TimeInterval) -> String? {
        LRC.line(at: time, in: lines)?.text
    }

    func trackChanged(_ n: NowPlaying) {
        guard enabled, n.hasMedia, let title = n.title else {
            key = nil
            if !lines.isEmpty { lines = [] }
            return
        }
        let k = "\(n.artist ?? "")|\(title)"
        guard k != key else { return }
        key = k
        lines = []
        task?.cancel()
        task = Task { [weak self] in
            guard let fetched = await Self.fetch(title: title, artist: n.artist, album: n.album, duration: n.duration),
                  let self, !Task.isCancelled, self.key == k else { return }
            self.lines = fetched
        }
    }

    private static func fetch(title: String, artist: String?, album: String?, duration: TimeInterval?) async -> [LyricLine]? {
        guard let artist else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if let album { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration, duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        components.queryItems = items
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Gobbl (https://gobbl.xeve.io)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let synced = object["syncedLyrics"] as? String else { return nil }
        let lines = LRC.parse(synced)
        return lines.isEmpty ? nil : lines
    }
}
