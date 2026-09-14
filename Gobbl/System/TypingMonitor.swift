import AppKit

/// Lets Gob react while you type anywhere on the Mac. Opt-in, and macOS only
/// delivers other apps' keystrokes to apps with Accessibility permission.
/// Only the fact that a key went down is used — never which key — and secure
/// fields (passwords) aren't delivered to any app at all.
@MainActor
enum TypingMonitor {
    private static var monitor: Any?

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "reactToTyping") }

    static func apply() {
        if enabled && MediaKeyTap.isTrusted {
            guard monitor == nil else { return }
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                guard !event.isARepeat else { return }
                MainActor.assumeIsolated { PetModel.shared.keyPressed() }
            }
        } else if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
