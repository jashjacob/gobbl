import AppKit
import GobblCore

/// A tap of the Gobbl key: write, rewrite, draft or answer in the focused
/// field, depending on what's there (see `WriteMode`).
@MainActor
enum WriteAction {
    private static var running = false
    /// For "Paste Last Result" when a write didn't land.
    private(set) static var lastResult: String?

    static func run() {
        guard !running else { return }
        guard AIClient.shared.isRegistered else {
            HUDModel.shared.show(.init(symbol: "sparkles", label: "AI: Settings", tint: Palette.gold), for: 3)
            return
        }
        guard let target = FieldIO.capture() else {
            HUDModel.shared.show(.init(symbol: "character.cursor.ibeam", label: "No text field", tint: Palette.gold), for: 2)
            return
        }
        let snapshot = target.snapshot
        if FieldIO.isTerminal(snapshot.bundleID) && snapshot.selection.isEmpty {
            HUDModel.shared.show(.init(symbol: "character.cursor.ibeam", label: "Select text first", tint: Palette.gold), for: 2.5)
            return
        }
        let mode = WriteMode.for(snapshot)
        guard mode.text(from: snapshot).count <= 10_000 else {
            HUDModel.shared.show(.init(symbol: "text.badge.xmark", label: "Too much text", tint: Palette.gold), for: 2.5)
            return
        }
        running = true
        PetModel.shared.send(.assistantBusy(true))
        HUDModel.shared.show(.init(symbol: "pencil.and.scribble", label: label(for: mode), tint: Palette.accent), for: 30)

        var context: [String: Any] = ["app": snapshot.appName, "windowTitle": snapshot.windowTitle,
                                      "nearbyText": String(snapshot.nearbyText.suffix(3000))]
        if let url = snapshot.url { context["url"] = url }
        var body: [String: Any] = ["mode": mode.rawValue, "text": mode.text(from: snapshot), "context": context,
                                   "locale": AIClient.locale]
        if mode == .rewrite { body["selection"] = snapshot.selection }

        Task {
            defer {
                running = false
                PetModel.shared.send(.assistantBusy(false))
            }
            do {
                let result = try await AIClient.shared.complete("/v1/write", body: body)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else {
                    HUDModel.shared.show(.init(symbol: "exclamationmark.triangle.fill", label: "Nothing to add", tint: Palette.gold), for: 2)
                    return
                }
                lastResult = result
                let placement: FieldIO.Placement = mode.replacesWholeField ? .wholeField : .selectionOrCaret
                await FieldIO.write(result, into: target, placement: placement)
                HUDModel.shared.show(.init(symbol: "checkmark.circle.fill", label: "Done", tint: Palette.accent), for: 1.5)
                PetModel.shared.send(.pluggedIn) // a small happy hop
            } catch {
                let message = (error as? AIClient.AIError)?.errorDescription ?? error.localizedDescription
                HUDModel.shared.show(.init(symbol: "exclamationmark.triangle.fill", label: short(message), tint: Palette.gold), for: 3.5)
            }
        }
    }

    /// Menu bar and notch: put the last result in wherever the cursor is now.
    static func pasteLast() {
        guard let lastResult else { return }
        Task { await FieldIO.paste(lastResult) }
    }

    private static func label(for mode: WriteMode) -> String {
        switch mode {
        case .instruction: "Writing"
        case .rewrite: "Rewriting"
        case .draft: "Drafting"
        case .answer: "Answering"
        }
    }

    private static func short(_ s: String) -> String { s.count > 14 ? String(s.prefix(13)) + "…" : s }
}
