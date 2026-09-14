import AppKit
import ApplicationServices
import GobblCore
import Observation
import os

private let log = Logger(subsystem: "com.xeve.gobbl", category: "memory")

/// Gobbl's memory: off until the user turns it on. Watches which window is
/// in front (app switches, window and focus changes, a slow backstop while
/// the user is active) and asks the capture engine to read it.
@MainActor @Observable
final class MemoryModel {
    static let shared = MemoryModel()

    enum Keys {
        static let enabled = "memoryEnabled"
        static let pausedUntil = "memoryPausedUntil"
        static let excludedApps = "memoryExcludedApps"
        static let includedApps = "memoryIncludedApps"
        static let excludedDomains = "memoryExcludedDomains"
        static let excludedChats = "memoryExcludedChats"
        static let retentionDays = "memoryRetentionDays"
        static let quietLargeGroups = "memoryQuietLargeGroups"
    }

    static let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Gobbl/memory.sqlite")

    private(set) var isCapturing = false
    private(set) var pausedUntil: Date?
    private(set) var lastStored: Date?
    private(set) var stats: MemoryStore.Stats?
    /// Apps seen while capturing, for the per-app list in Settings.
    private(set) var seenApps: [String: String] = [:]

    @ObservationIgnored private(set) var store: MemoryStore?
    @ObservationIgnored private var engine: CaptureEngine?
    @ObservationIgnored private var activation: NSObjectProtocol?
    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var observedPID: pid_t = 0
    @ObservationIgnored private var backstop: Timer?
    @ObservationIgnored private var resumeTimer: Timer?

    var enabled: Bool { UserDefaults.standard.bool(forKey: Keys.enabled) }
    var isPaused: Bool { pausedUntil.map { $0 > Date() } ?? false }

    private init() {
        pausedUntil = UserDefaults.standard.object(forKey: Keys.pausedUntil) as? Date
        seenApps = UserDefaults.standard.dictionary(forKey: "memorySeenApps") as? [String: String] ?? [:]
    }

    // MARK: Lifecycle

    func apply() {
        if enabled && MediaKeyTap.isTrusted && !isPaused { start() } else { stop() }
        if isPaused, let until = pausedUntil { scheduleResume(at: until) }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Keys.enabled)
        if on && !MediaKeyTap.isTrusted { MediaKeyTap.requestTrust() }
        apply()
    }

    private func start() {
        guard engine == nil else { return }
        do {
            let store = try self.store ?? MemoryStore(url: Self.storeURL)
            self.store = store
            let engine = CaptureEngine(store: store)
            engine.onStored = { [weak self] count, _ in self?.didStore(count) }
            self.engine = engine
            pushSettings()
        } catch {
            log.error("memory store failed to open: \(error.localizedDescription, privacy: .public)")
            return
        }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MemoryModel.shared.frontmostChanged() }
        }
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { MemoryModel.shared.captureFrontmost(delay: 0.2) }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        backstop = timer
        isCapturing = true
        frontmostChanged()
        applyRetention()
        refreshStats()
    }

    private func stop() {
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        removeObserver()
        backstop?.invalidate()
        backstop = nil
        engine = nil
        isCapturing = false
    }

    // MARK: Pause

    func pause(for duration: TimeInterval?) {
        let until = duration.map { Date().addingTimeInterval($0) } ?? Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        pausedUntil = until
        UserDefaults.standard.set(until, forKey: Keys.pausedUntil)
        stop()
        scheduleResume(at: until)
    }

    func resume() {
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: Keys.pausedUntil)
        resumeTimer?.invalidate()
        apply()
    }

    private func scheduleResume(at date: Date) {
        resumeTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { MemoryModel.shared.resume() }
        }
        RunLoop.main.add(timer, forMode: .common)
        resumeTimer = timer
    }

    // MARK: Triggers

    private func frontmostChanged() {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier else { return }
        if app.processIdentifier != observedPID { observe(app.processIdentifier) }
        if seenApps[bundle] == nil, !CaptureRules.deniedApps.contains(bundle) {
            seenApps[bundle] = Self.cleanName(app.localizedName ?? bundle)
            UserDefaults.standard.set(seenApps, forKey: "memorySeenApps")
        }
        captureFrontmost(delay: 1.5)
    }

    fileprivate func captureFrontmost(delay: TimeInterval) {
        guard let engine, let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier else { return }
        engine.schedule(CaptureTarget(pid: app.processIdentifier, bundleID: bundle, appName: Self.cleanName(app.localizedName ?? bundle)), delay: delay)
    }

    /// Some apps (WhatsApp) put invisible direction marks in their names.
    nonisolated static func cleanName(_ name: String) -> String {
        name.unicodeScalars.filter { !["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"].contains($0) }
            .map(String.init).joined().trimmingCharacters(in: .whitespaces)
    }

    /// One AXObserver on the frontmost app: window, focus and title changes.
    private func observe(_ pid: pid_t) {
        removeObserver()
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { MemoryModel.shared.captureFrontmost(delay: 1.5) } }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        for name in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXTitleChangedNotification,
                     kAXWindowCreatedNotification, "AXLoadComplete", "AXLayoutChanged"] {
            AXObserverAddNotification(created, app, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
    }

    private func removeObserver() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        observedPID = 0
    }

    /// The user just typed something (TypingMonitor): chats update as you send.
    func userTyped() {
        guard isCapturing else { return }
        captureFrontmost(delay: 3)
    }

    private func didStore(_ count: Int) {
        lastStored = Date()
        TodoCenter.shared.checkResolution()
        if let s = stats { stats = MemoryStore.Stats(chunks: s.chunks + count, segments: s.segments, bytes: s.bytes) }
    }

    // MARK: Settings

    func pushSettings() {
        let d = UserDefaults.standard
        var s = CaptureSettings()
        s.excludedApps = Set(d.stringArray(forKey: Keys.excludedApps) ?? [])
        s.includedApps = Set(d.stringArray(forKey: Keys.includedApps) ?? [])
        s.excludedDomains = Set(d.stringArray(forKey: Keys.excludedDomains) ?? [])
        s.excludedChats = Set(d.stringArray(forKey: Keys.excludedChats) ?? [])
        s.quietLargeGroups = d.object(forKey: Keys.quietLargeGroups) as? Bool ?? true
        s.me = Set(Self.myNames)
        engine?.update(s)
    }

    /// Names the user appears under in chats: what they typed in Settings,
    /// what Gobbl learned, and the Mac account's name.
    nonisolated static var myNames: [String] {
        let typed = (UserDefaults.standard.string(forKey: "memoryMyNames") ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let full = NSFullUserName()
        return (typed + [full, full.components(separatedBy: " ").first ?? full, "You"]).filter { $0.count >= 2 }
    }

    /// WhatsApp showed who the user is (the one name opposite many others): remember it.
    func learnMyName(_ name: String) {
        let d = UserDefaults.standard
        var typed = (d.string(forKey: "memoryMyNames") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !typed.contains(where: { EntityRules.normalize($0) == EntityRules.normalize(name) }) else { return }
        typed.append(name)
        d.set(typed.joined(separator: ", "), forKey: "memoryMyNames")
        pushSettings()
        log.info("learned the user's chat name")
    }

    func setApp(_ bundleID: String, allowed: Bool) {
        let d = UserDefaults.standard
        var excluded = Set(d.stringArray(forKey: Keys.excludedApps) ?? [])
        var included = Set(d.stringArray(forKey: Keys.includedApps) ?? [])
        if allowed {
            excluded.remove(bundleID)
            included.insert(bundleID)
        } else {
            excluded.insert(bundleID)
            included.remove(bundleID)
        }
        d.set(Array(excluded), forKey: Keys.excludedApps)
        d.set(Array(included), forKey: Keys.includedApps)
        pushSettings()
    }

    func isAllowed(_ bundleID: String) -> Bool {
        let d = UserDefaults.standard
        if (d.stringArray(forKey: Keys.excludedApps) ?? []).contains(bundleID) { return false }
        if (d.stringArray(forKey: Keys.includedApps) ?? []).contains(bundleID) { return true }
        let kind = CaptureRules.kind(of: bundleID)
        return kind != .code && kind != .terminal
    }

    #if DEBUG
    /// For self-tests: work against a throwaway store.
    func useStoreForTesting(_ store: MemoryStore) {
        self.store = store
    }
    #endif

    // MARK: Forgetting and retention

    func forget(last seconds: TimeInterval?) {
        guard let store = try? store ?? MemoryStore(url: Self.storeURL) else { return }
        self.store = store
        if let seconds { try? store.forget(from: Date().addingTimeInterval(-seconds)) } else { try? store.forgetAll() }
        refreshStats()
        HUDModel.shared.show(.init(symbol: "eraser.fill", label: "Forgotten", tint: Palette.accent), for: 2)
    }

    func forget(app bundleID: String) {
        try? store?.forget(appBundle: bundleID)
        refreshStats()
    }

    /// 0 means keep forever (the default).
    var retentionDays: Int { UserDefaults.standard.integer(forKey: Keys.retentionDays) }

    func applyRetention() {
        guard retentionDays > 0, let store else { return }
        try? store.forget(from: .distantPast, to: Date().addingTimeInterval(-Double(retentionDays) * 86400))
    }

    func refreshStats() {
        stats = try? (store ?? (FileManager.default.fileExists(atPath: Self.storeURL.path) ? MemoryStore(url: Self.storeURL) : nil))?.stats()
    }
}
