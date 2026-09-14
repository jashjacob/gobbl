import AppKit
import GobblCore
import Observation

/// Now playing for every app (Music, Spotify, browsers…) through the bundled
/// mediaremote-adapter, run by /usr/bin/perl — the one binary still entitled
/// to MediaRemote on macOS 15.4+. The stream process idles until something
/// changes, so this costs nothing while music plays.
@MainActor @Observable
final class MediaController {
    static let shared = MediaController()

    private(set) var nowPlaying = NowPlaying()
    private(set) var artwork: NSImage?
    /// False when the adapter is missing or keeps dying (e.g. a macOS update broke it).
    private(set) var available = true

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stream = NowPlayingStream()
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var restarts = 0
    @ObservationIgnored private var artworkHash: Int?
    @ObservationIgnored private var stopping = false

    private var script: URL? { Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl") }
    private var framework: URL? { Bundle.main.url(forResource: "MediaRemoteAdapter", withExtension: "framework") }

    func start() {
        guard RemoteFlags.mediaRemote else {
            available = false
            return
        }
        guard process == nil, let script, let framework else {
            if script == nil || framework == nil { available = false }
            return
        }
        stopping = false
        killStale(framework)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, framework.path, "stream", "--debounce=80"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.terminated() } }
        }
        do {
            try p.run()
            process = p
            available = true
        } catch {
            available = false
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
    }

    // MARK: Commands (MRCommand IDs, see Vendor/mediaremote-adapter README)

    func togglePlayPause() { run(["send", "2"]) }
    func next() { run(["send", "4"]) }
    func previous() { run(["send", "5"]) }

    func seek(to seconds: TimeInterval) {
        run(["seek", String(Int(max(0, seconds) * 1_000_000))])
    }

    var appIcon: NSImage? {
        guard let id = nowPlaying.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var appName: String? {
        guard let id = nowPlaying.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func openPlayer() {
        guard let id = nowPlaying.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Private

    private func run(_ args: [String]) {
        guard let script, let framework else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, framework.path] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// macOS has no "die with parent": a stream left by a crashed or force-quit
    /// Gobbl only exits on its next write. Clear any before starting ours.
    private func killStale(_ framework: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "\(framework.path) stream"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if stream.apply(line: line) { update(stream.current) }
        }
    }

    private func update(_ n: NowPlaying) {
        let wasPlaying = nowPlaying.playing
        nowPlaying = n
        let hash = n.artworkData?.hashValue
        if hash != artworkHash {
            artworkHash = hash
            artwork = n.artworkData.flatMap { NSImage(data: $0) }
        }
        if n.playing != wasPlaying { PetModel.shared.send(.musicPlaying(n.playing)) }
        LyricsModel.shared.trackChanged(n)
        restarts = 0
    }

    private func terminated() {
        process = nil
        buffer.removeAll()
        guard !stopping else { return }
        guard restarts < 5 else {
            available = false
            return
        }
        restarts += 1
        let delay = Double(restarts * 2)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.start()
        }
    }
}
