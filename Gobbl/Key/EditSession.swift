import AppKit
import GobblCore
import Observation

/// Edit mode: double-tap the Gobbl key and the notch opens on the text you're
/// working on. Type or say how to change it ("tighter", "in Hindi"); each
/// instruction makes a new version, the arrows step between them, and
/// Replace puts the chosen one back into the field.
@MainActor @Observable
final class EditSession {
    static let shared = EditSession()

    private(set) var appName = ""
    private(set) var versions: [String] = []
    private(set) var index = 0
    /// Text arriving from the AI for the version being made.
    private(set) var streaming: String?
    private(set) var error: String?
    var instruction = ""

    private var target: FieldIO.Target?
    private var usesSelection = false
    private var task: Task<Void, Never>?

    var draft: String { versions.indices.contains(index) ? versions[index] : "" }
    var busy: Bool { streaming != nil }
    var canReplace: Bool { index > 0 && !busy }

    static let suggestions = ["Shorter", "Friendlier", "More formal", "Fix grammar", "Bullet points"]

    func begin() {
        guard AIClient.shared.isRegistered else {
            HUDModel.shared.show(.init(symbol: "sparkles", label: "AI: Settings", tint: Palette.gold), for: 3)
            return
        }
        guard let field = FieldIO.capture() else {
            HUDModel.shared.show(.init(symbol: "character.cursor.ibeam", label: "No text field", tint: Palette.gold), for: 2)
            return
        }
        usesSelection = !field.snapshot.selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let text = usesSelection ? field.snapshot.selection : field.snapshot.value
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            HUDModel.shared.show(.init(symbol: "text.cursor", label: "Nothing to edit", tint: Palette.gold), for: 2)
            return
        }
        target = field
        appName = field.snapshot.appName
        versions = [text]
        index = 0
        instruction = ""
        error = nil
        // Holding the Gobbl key while the editor is open speaks an instruction.
        Dictation.shared.routeSpeech(to: "edit") { [weak self] spoken in
            self?.instruction = spoken
            self?.submit()
        }
        NotchController.shared.open(tab: .edit)
    }

    func submit() {
        let ask = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty, !busy, let target else { return }
        error = nil
        streaming = ""
        PetModel.shared.send(.assistantBusy(true))
        var context: [String: Any] = ["app": target.snapshot.appName, "windowTitle": target.snapshot.windowTitle]
        if let url = target.snapshot.url { context["url"] = url }
        let body: [String: Any] = ["text": draft, "instruction": ask, "context": context, "locale": AIClient.locale]
        task = Task {
            defer {
                streaming = nil
                PetModel.shared.send(.assistantBusy(false))
            }
            do {
                for try await delta in AIClient.shared.stream("/v1/edit", body: body) {
                    streaming = (streaming ?? "") + delta
                }
                let result = (streaming ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { return }
                versions = Array(versions.prefix(index + 1)) + [result]
                index = versions.count - 1
                instruction = ""
            } catch {
                self.error = (error as? AIClient.AIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func suggest(_ text: String) {
        instruction = text
        submit()
    }

    func step(_ delta: Int) {
        guard !busy else { return }
        index = max(0, min(versions.count - 1, index + delta))
    }

    /// Puts the chosen version into the field and closes.
    func replace() {
        guard canReplace, let target else { return }
        let text = draft
        let placement: FieldIO.Placement = usesSelection ? .selectionOrCaret : .wholeField
        end()
        Task {
            await FieldIO.write(text, into: target, placement: placement)
            PetModel.shared.send(.pluggedIn)
        }
    }

    func end() {
        task?.cancel()
        detach()
        NotchController.shared.closeAll()
    }

    /// The editor went away (Esc, a click outside): stop listening for it.
    func detach() {
        Dictation.shared.stopRouting("edit")
        target = nil
    }
}
