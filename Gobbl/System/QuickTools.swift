import AppKit
import Observation
import SwiftUI

/// One-click utilities on the Tools tab: mic mute, color picker, and copying
/// text from any part of the screen.
@MainActor @Observable
final class QuickTools {
    static let shared = QuickTools()

    private(set) var micMuted = AudioDevices.micMuted

    func toggleMic() {
        AudioDevices.setMicMuted(!AudioDevices.micMuted)
        micMuted = AudioDevices.micMuted
        HUDModel.shared.show(.init(symbol: micMuted ? "mic.slash.fill" : "mic.fill", label: micMuted ? "Muted" : "Live",
                                   tint: micMuted ? .red : Palette.accent), for: 1.5)
    }

    func refreshMic() { micMuted = AudioDevices.micMuted }

    /// The system color sampler; the picked color's hex goes to the clipboard.
    func pickColor() {
        NotchController.shared.closeAll()
        NSColorSampler().show { color in
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                             Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            MainActor.assumeIsolated {
                HUDModel.shared.show(.init(symbol: "circle.fill", label: hex, tint: Color(nsColor: c)), for: 2.5)
            }
        }
    }

    /// Drag a box around text on screen (the system screenshot picker); Gob copies the text.
    func captureScreenText() {
        NotchController.shared.closeAll()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-screen-text.png")
        try? FileManager.default.removeItem(at: url)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-x", url.path]
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Escape cancels the selection: no file, nothing to do.
                    guard FileManager.default.fileExists(atPath: url.path) else { return }
                    FileActions.copyText([url])
                }
            }
        }
        try? p.run()
    }
}
