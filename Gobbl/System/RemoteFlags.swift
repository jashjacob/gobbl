import Foundation

/// A remote off switch for fragile features, read from
/// https://dl.xeve.io/gobbl/flags.json (published by scripts/release.sh).
/// If a macOS update breaks the MediaRemote adapter, setting
/// `"mediaRemote": false` there stops Gobbl running it without a new release.
/// Fetched with the update check, and only when automatic update checks are on.
@MainActor
enum RemoteFlags {
    static let url = URL(string: "https://dl.xeve.io/gobbl/flags.json")!

    static var mediaRemote: Bool { UserDefaults.standard.object(forKey: "flag.mediaRemote") as? Bool ?? true }

    static func refresh() {
        guard Updater.shared.automaticallyChecks else { return }
        Task {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue("Gobbl/\(Updater.versionString)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let flags = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let on = flags["mediaRemote"] as? Bool {
                UserDefaults.standard.set(on, forKey: "flag.mediaRemote")
                if on { MediaController.shared.start() } else { MediaController.shared.stop() }
            }
        }
    }
}
