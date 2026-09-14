import AppKit
import Carbon.HIToolbox
import GobblCore
import os

private let log = Logger(subsystem: "com.xeve.gobbl", category: "memory")

/// The app whose window is to be read.
struct CaptureTarget: Sendable, Equatable {
    let pid: pid_t
    let bundleID: String
    let appName: String
}

/// What the user allowed, handed to the capture queue as a value.
struct CaptureSettings: Sendable {
    var excludedApps: Set<String> = []
    var excludedDomains: Set<String> = []
    var excludedChats: Set<String> = []
    /// Apps of these kinds are skipped unless the user turned them on.
    var skippedKinds: Set<CaptureAppKind> = [.code, .terminal]
    var includedApps: Set<String> = []
    /// Names the user appears under in chats (their own messages).
    var me: Set<String> = []
    /// Busy group chats: keep only the user's own messages and ones naming them.
    var quietLargeGroups = true
}

/// Reads the focused window after things settle, turns it into messages or
/// lines, masks secrets, drops what was already stored, and saves the rest.
/// Everything here runs on one background queue.
final class CaptureEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.xeve.gobbl.capture", qos: .utility)
    private let store: MemoryStore
    private var settings = CaptureSettings()
    private var pending: DispatchWorkItem?
    private var lastCapture: [String: Date] = [:]
    private var dedup: [String: LineDedup] = [:]
    private var segments: [String: (id: Int64, last: Date)] = [:]
    private var manualAX: Set<pid_t> = []

    /// Called on the main queue after each capture that stored something.
    var onStored: (@MainActor (Int, String) -> Void)?

    init(store: MemoryStore) {
        self.store = store
    }

    func update(_ settings: CaptureSettings) {
        queue.async { self.settings = settings }
    }

    /// Captures `target` once things have been quiet for `delay`.
    func schedule(_ target: CaptureTarget, delay: TimeInterval = 1.5) {
        queue.async {
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.capture(target) }
            self.pending = work
            self.queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: Capture

    private func capture(_ target: CaptureTarget, retry: Bool = true) {
        let s = settings
        let kind = CaptureRules.kind(of: target.bundleID)
        guard !CaptureRules.deniedApps.contains(target.bundleID), !s.excludedApps.contains(target.bundleID),
              !s.skippedKinds.contains(kind) || s.includedApps.contains(target.bundleID) else { return }
        guard !IsSecureEventInputEnabled(), !Self.screenLocked, Self.idleSeconds < 120 else { return }

        if isElectron(target), !manualAX.contains(target.pid) {
            AXSnapshot.enableManualAccessibility(pid: target.pid)
            manualAX.insert(target.pid)
        }
        // Chat apps get a longer budget: Messages answers slowly and the
        // conversation comes after the chat list. Still off the main thread.
        guard let snap = AXSnapshot.focusedWindow(pid: target.pid, withGeometry: kind == .messaging,
                                                  skipEditable: kind == .messaging || kind == .mail,
                                                  budget: kind == .messaging ? 0.4 : 0.15) else { return }
        if snap.nodes.isEmpty {
            // Chromium fills its tree in asynchronously after being asked.
            if retry { queue.asyncAfter(deadline: .now() + 0.25) { self.capture(target, retry: false) } }
            return
        }
        if kind == .browser, CaptureRules.isPrivateWindow(title: snap.title) { return }
        let domain = CaptureRules.domain(of: snap.url)
        if CaptureRules.isDeniedDomain(domain, extra: s.excludedDomains) { return }

        var parsed: [ChatMessage] = []
        var chat = kind == .messaging ? MessagingParser.chatName(windowTitle: snap.title.strippingBidiMarks, appName: target.appName) : nil
        if kind == .messaging {
            parsed = MessagingParser.parse(bundleID: target.bundleID, nodes: snap.nodes, me: s.me)
            if let learned = learnMe(from: parsed) {
                // Found who the user is: read this window again with that.
                settings.me.insert(learned)
                parsed = MessagingParser.parse(bundleID: target.bundleID, nodes: snap.nodes, me: settings.me)
                DispatchQueue.main.async { MainActor.assumeIsolated { MemoryModel.shared.learnMyName(learned) } }
            }
            // No name in the title (WhatsApp): a one-to-one chat is named after the other person.
            if chat == nil { chat = MessagingParser.chatFromSenders(parsed) }
        }
        if let chat, s.excludedChats.contains(chat) { return }

        let key = "\(target.bundleID)|\(snap.title)|\(chat ?? "")"
        let now = Date()
        if let last = lastCapture[key], now.timeIntervalSince(last) < 5 { return }
        lastCapture[key] = now
        if lastCapture.count > 400 { lastCapture = lastCapture.filter { now.timeIntervalSince($0.value) < 600 } }

        var seen = dedup[key] ?? LineDedup(capacity: 3000)
        var chunks: [MemoryStore.NewChunk] = []
        if kind == .messaging {
            var messages = parsed
            if s.quietLargeGroups, Set(messages.compactMap(\.sender)).count >= 6 {
                let names = s.me.map { $0.lowercased() }
                messages = messages.filter { m in m.fromMe || names.contains { m.text.lowercased().contains($0) } }
            }
            for m in messages {
                let id = "\(m.fromMe ? "me" : (m.sender ?? "?"))|\(m.text)"
                guard !seen.fresh([id]).isEmpty else { continue }
                chunks.append(.init(ts: now, kind: "message", sender: m.sender, fromMe: m.fromMe, text: Redactor.redact(m.text)))
            }
        } else {
            let fresh = seen.fresh(GenericParser.lines(snap.nodes))
            for block in Self.blocks(fresh, maxChars: 800) {
                chunks.append(.init(ts: now, kind: kind == .mail ? "mail" : "text", text: Redactor.redact(block)))
            }
        }
        dedup[key] = seen
        if dedup.count > 60 { dedup.removeAll() }
        guard !chunks.isEmpty else { return }

        do {
            let segment: Int64
            if let existing = segments[key], now.timeIntervalSince(existing.last) < 300 {
                segment = existing.id
            } else {
                segment = try store.beginSegment(appBundle: target.bundleID, appName: target.appName, window: snap.title,
                                                 url: snap.url, chat: chat, at: now)
            }
            segments[key] = (segment, now)
            try store.addChunks(segment: segment, chunks)
            log.info("captured \(chunks.count) chunks from \(target.appName, privacy: .public) in \(Int(snap.elapsed * 1000))ms\(snap.truncated ? " (truncated)" : "")")
            let count = chunks.count
            let app = target.appName
            DispatchQueue.main.async { [onStored] in
                MainActor.assumeIsolated { onStored?(count, app) }
            }
        } catch {
            log.error("store failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Two-person chats where neither name is known to be the user: the name
    /// that keeps appearing opposite different people (three or more) is them.
    private var partners: [String: Set<String>] = [:]

    private func learnMe(from messages: [ChatMessage]) -> String? {
        guard !messages.contains(where: \.fromMe) else { return nil }
        let names = Array(Set(messages.compactMap(\.sender)))
        guard names.count == 2 else { return nil }
        partners[names[0], default: []].insert(names[1])
        partners[names[1], default: []].insert(names[0])
        if partners.count > 500 { partners.removeAll() }
        return names.first { (partners[$0]?.count ?? 0) >= 3 }
    }

    /// Consecutive lines grouped into chunks of about `maxChars`.
    static func blocks(_ lines: [String], maxChars: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for line in lines {
            if !current.isEmpty, current.count + line.count + 1 > maxChars {
                out.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private func isElectron(_ target: CaptureTarget) -> Bool {
        guard let url = NSRunningApplication(processIdentifier: target.pid)?.bundleURL else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
            || ["com.microsoft.teams2", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser"].contains(target.bundleID)
    }

    static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// Seconds since the last keyboard or mouse input anywhere.
    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
