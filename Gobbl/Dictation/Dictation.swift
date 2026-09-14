import AppKit
import GobblCore
import Observation
// WhisperKit's classes aren't marked Sendable; Gobbl only touches them from the main actor.
@preconcurrency import WhisperKit

/// Hold the Gobbl key and talk; let go and the text goes where your cursor
/// is. Whisper runs on this Mac (WhisperKit), so the voice never leaves it.
///
/// Recording starts the moment the hold is recognised, with its own audio
/// processor, so nothing is lost while the model wakes up. The model stays
/// warm between uses and is unloaded after a quiet half hour.
@MainActor @Observable
final class Dictation {
    static let shared = Dictation()

    enum ModelChoice: String, CaseIterable, Identifiable {
        case turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"
        case base = "openai_whisper-base"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .turbo: "Best: Whisper Turbo (about 630 MB)"
            case .base: "Fast: Whisper Base (about 150 MB)"
            }
        }
    }

    // MARK: State for the UI

    private(set) var isRecording = false
    private(set) var downloadProgress: Double?
    private(set) var status: String?
    private(set) var installedModel: ModelChoice?
    /// This session's dictations, newest first, for re-pasting. Kept in memory only.
    private(set) var history: [String] = []
    /// When set (edit mode or chat is open), dictated text goes here instead of into a field.
    @ObservationIgnored private(set) var redirect: ((String) -> Void)?
    @ObservationIgnored private var redirectOwner: String?

    func routeSpeech(to owner: String, _ handler: @escaping (String) -> Void) {
        redirectOwner = owner
        redirect = handler
    }

    /// Only the owner can stop it, so switching tabs doesn't cancel the new one.
    func stopRouting(_ owner: String) {
        guard redirectOwner == owner else { return }
        redirectOwner = nil
        redirect = nil
    }

    static var supported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    var style: DictationStyle {
        DictationStyle(rawValue: UserDefaults.standard.string(forKey: "dictationStyle") ?? "") ?? .light
    }

    // MARK: Private

    private static let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Gobbl/Models", isDirectory: true)

    private let audio = AudioProcessor()
    private var whisper: WhisperKit?
    private var loading: Task<Loaded, Error>?
    private var downloadTask: Task<Void, Never>?
    private var unloadTimer: Timer?
    private var target: FieldIO.Target?
    private var locked = false
    private var startedAt = Date()
    private var peakEnergy: Float = 0

    private var installedFolder: String? {
        guard let path = UserDefaults.standard.string(forKey: "dictationModelFolder"),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private init() {
        if installedFolder != nil {
            installedModel = ModelChoice(rawValue: UserDefaults.standard.string(forKey: "dictationModelInstalled") ?? "")
        }
    }

    // MARK: Model

    func downloadModel(_ choice: ModelChoice) {
        guard downloadTask == nil else { return }
        downloadProgress = 0
        status = nil
        downloadTask = Task {
            do {
                try FileManager.default.createDirectory(at: Self.modelsDir, withIntermediateDirectories: true)
                let folder = try await WhisperKit.download(variant: choice.rawValue, downloadBase: Self.modelsDir) { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in Dictation.shared.downloadProgress = fraction }
                }
                UserDefaults.standard.set(folder.path, forKey: "dictationModelFolder")
                UserDefaults.standard.set(choice.rawValue, forKey: "dictationModelInstalled")
                whisper = nil
                installedModel = choice
                downloadProgress = nil
                status = "Ready. Hold right ⌥ to dictate."
                _ = try? await load()
            } catch {
                downloadProgress = nil
                status = "Download failed: \(error.localizedDescription)"
            }
            downloadTask = nil
        }
    }

    func removeModel() {
        Task { await whisper?.unloadModels() }
        whisper = nil
        loading = nil
        if let folder = installedFolder { try? FileManager.default.removeItem(atPath: folder) }
        UserDefaults.standard.removeObject(forKey: "dictationModelFolder")
        UserDefaults.standard.removeObject(forKey: "dictationModelInstalled")
        installedModel = nil
        status = nil
    }

    /// Loads the model ahead of the first hold, so the first dictation is quick.
    func warmUp() {
        guard Self.supported, installedFolder != nil, whisper == nil else { return }
        Task { _ = try? await load() }
        scheduleUnload()
    }

    /// WhisperKit isn't Sendable; the box lets the loaded model cross back to
    /// the main actor, which is the only place Gobbl uses it.
    private final class Loaded: @unchecked Sendable {
        let kit: WhisperKit
        init(_ kit: WhisperKit) { self.kit = kit }
    }

    private func load() async throws -> WhisperKit {
        if let whisper { return whisper }
        if let loading { return try await loading.value.kit }
        guard let folder = installedFolder else { throw DictationError.noModel }
        let task = Task { () throws -> Loaded in
            Loaded(try await WhisperKit(WhisperKitConfig(modelFolder: folder, verbose: false, logLevel: .error,
                                                         prewarm: true, load: true, download: false)))
        }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value.kit
        whisper = loaded
        return loaded
    }

    private func scheduleUnload() {
        unloadTimer?.invalidate()
        unloadTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: false) { _ in
            MainActor.assumeIsolated {
                let dictation = Dictation.shared
                guard !dictation.isRecording, let whisper = dictation.whisper else { return }
                dictation.whisper = nil
                Task { await whisper.unloadModels() }
            }
        }
    }

    enum DictationError: LocalizedError {
        case noModel
        var errorDescription: String? { "Set up dictation in Settings first." }
    }

    // MARK: Recording

    /// `locked`: double-tap-and-hold, which keeps listening after release
    /// until the next tap or a few seconds of silence.
    func start(locked: Bool) {
        guard Self.supported else {
            HUDModel.shared.show(.init(symbol: "mic.slash.fill", label: "Needs M-series", tint: Palette.gold), for: 2.5)
            return
        }
        if isRecording {
            // Held again while hands-free: back to push-to-talk, release ends it.
            self.locked = false
            return
        }
        guard installedFolder != nil else {
            // A hint, not a window: a stray hold shouldn't throw Settings in the user's face.
            HUDModel.shared.show(.init(symbol: "mic.fill", label: "Dictation: Settings", tint: Palette.gold), for: 3)
            return
        }
        target = redirect == nil ? FieldIO.capture() : nil
        self.locked = locked
        isRecording = true
        startedAt = Date()
        peakEnergy = 0
        unloadTimer?.invalidate()
        PetModel.shared.send(.dictating(true))
        HUDModel.shared.show(.init(symbol: locked ? "lock.fill" : "mic.fill", label: locked ? "Hands-free" : "Listening",
                                   tint: Palette.accent), for: 600)
        Task {
            guard await AudioProcessor.requestRecordPermission() else {
                cancel(message: "Microphone is off")
                return
            }
            guard isRecording else { return }
            do {
                try audio.startRecordingLive(inputDeviceID: nil) { _ in
                    Task { @MainActor in Dictation.shared.meter() }
                }
            } catch {
                cancel(message: "Mic unavailable")
            }
        }
        // Wake the model while the user talks.
        Task { _ = try? await load() }
    }

    /// Key released (push-to-talk), tapped (hands-free) or silence.
    func release() {
        guard isRecording, !locked else { return }
        finish()
    }

    func stopHandsFree() {
        guard isRecording else { return }
        finish()
    }

    private func meter() {
        guard isRecording else { return }
        let energy = audio.relativeEnergy
        let level = energy.last ?? 0
        MicLevel.value = level
        peakEnergy = max(peakEnergy, level)
        // Hands-free stops itself after about three seconds of quiet, once something was said.
        if locked, Date().timeIntervalSince(startedAt) > 3, peakEnergy > 0.3,
           energy.count >= 20, energy.suffix(20).allSatisfy({ $0 < 0.12 }) {
            finish()
        }
    }

    private func cancel(message: String) {
        isRecording = false
        locked = false
        audio.stopRecording()
        MicLevel.value = 0
        PetModel.shared.send(.dictating(false))
        HUDModel.shared.show(.init(symbol: "mic.slash.fill", label: message, tint: Palette.gold), for: 2.5)
    }

    private func finish() {
        isRecording = false
        locked = false
        audio.stopRecording()
        MicLevel.value = 0
        PetModel.shared.send(.dictating(false))
        let samples = Array(audio.audioSamples)
        let duration = Double(samples.count) / Double(WhisperKit.sampleRate)
        let quiet = peakEnergy < 0.2
        guard duration >= 0.35 else {
            HUDModel.shared.show(.init(symbol: "mic.fill", label: "Hold to talk", tint: Palette.accent), for: 1.2)
            return
        }
        let target = self.target
        PetModel.shared.send(.assistantBusy(true))
        HUDModel.shared.show(.init(symbol: "waveform", label: "Transcribing", tint: Palette.accent), for: 30)
        Task {
            defer {
                PetModel.shared.send(.assistantBusy(false))
                scheduleUnload()
            }
            do {
                let whisper = try await load()
                let results = try await whisper.transcribe(audioArray: samples, decodeOptions: decodingOptions(for: whisper))
                var text = DictationCleanup.verbatim(results.map(\.text).joined(separator: " "))
                if text.isEmpty || (DictationCleanup.isLikelyHallucination(text) && (quiet || duration < 2.5)) {
                    HUDModel.shared.show(.init(symbol: "ear", label: "Didn't catch that", tint: Palette.gold), for: 2)
                    return
                }
                if let redirect {
                    HUDModel.shared.dismiss()
                    redirect(DictationCleanup.light(text))
                    return
                }
                switch style {
                case .verbatim: break
                case .light: text = DictationCleanup.light(text)
                case .polish: text = await polish(DictationCleanup.light(text), for: target)
                }
                history.insert(text, at: 0)
                if history.count > 20 { history.removeLast() }
                if let target {
                    await FieldIO.write(text, into: target, placement: .selectionOrCaret)
                } else {
                    await FieldIO.paste(text)
                }
                HUDModel.shared.show(.init(symbol: "checkmark.circle.fill", label: "\(text.split(separator: " ").count) words",
                                           tint: Palette.accent), for: 1.5)
            } catch {
                HUDModel.shared.show(.init(symbol: "exclamationmark.triangle.fill", label: "Dictation failed", tint: Palette.gold), for: 3)
                status = error.localizedDescription
            }
        }
    }

    func repaste(_ text: String) {
        Task { await FieldIO.paste(text) }
    }

    private func decodingOptions(for whisper: WhisperKit) -> DecodingOptions {
        let defaults = UserDefaults.standard
        let language = defaults.string(forKey: "dictationLanguage") ?? "auto"
        var promptTokens: [Int]?
        let words = (defaults.string(forKey: "dictationWords") ?? "").split(whereSeparator: { $0 == "," || $0.isNewline }).map(String.init)
        if let prompt = DictationCleanup.vocabularyPrompt(words), let tokenizer = whisper.tokenizer {
            promptTokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        return DecodingOptions(language: language == "auto" ? nil : language,
                               temperatureFallbackCount: 3,
                               usePrefillPrompt: true,
                               detectLanguage: language == "auto",
                               skipSpecialTokens: true,
                               withoutTimestamps: true,
                               promptTokens: promptTokens)
    }

    /// The AI rewrite for "Polish". Falls back to the light clean-up if the
    /// service is slow or unavailable, so dictation never gets stuck.
    private func polish(_ text: String, for target: FieldIO.Target?) async -> String {
        guard AIClient.shared.isRegistered, text.split(separator: " ").count >= 6 else { return text }
        // The accent hint lets the clean-up fix accent-driven mishearings.
        let body: [String: Any] = ["text": text, "style": "polish", "app": target?.snapshot.appName ?? "",
                                   "bundleId": target?.snapshot.bundleID ?? "", "locale": AIClient.locale,
                                   "accent": AIClient.locale]
        let result = await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await AIClient.shared.complete("/v1/cleanup", body: body) }
            group.addTask {
                try? await Task.sleep(for: .seconds(6))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        let polished = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return polished.isEmpty ? text : polished
    }
}
