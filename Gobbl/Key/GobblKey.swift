import AppKit
import GobblCore

/// The Gobbl key: right ⌥ on its own. Tap to write, double-tap for edit
/// mode, hold to dictate. Pressing any other key while it's down cancels, so
/// ⌥ still works as a modifier (⌥E → é). Needs Accessibility, like the HUDs.
@MainActor
final class GobblKey {
    static let shared = GobblKey()

    private var machine = GobblKeyMachine()
    private var monitors: [Any] = []
    private var ticker: Timer?
    private var rightOptionDown = false

    static var enabled: Bool { UserDefaults.standard.object(forKey: "gobblKeyEnabled") as? Bool ?? true }

    func apply() {
        if Self.enabled && MediaKeyTap.isTrusted { install() } else { remove() }
    }

    private func install() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(local) }
    }

    private func remove() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        ticker?.invalidate()
        ticker = nil
    }

    private func handle(_ event: NSEvent) {
        let t = event.timestamp // system uptime, same clock as the ticker
        switch event.type {
        case .flagsChanged where event.keyCode == 61:
            // NX_DEVICERALTKEYMASK: right ⌥ specifically.
            let down = event.modifierFlags.rawValue & 0x40 != 0
            guard down != rightOptionDown else { return }
            rightOptionDown = down
            dispatch(machine.handle(down ? .down(t) : .up(t)))
        case .flagsChanged, .keyDown:
            // Another key or modifier: ⌥ is being used as a modifier.
            dispatch(machine.handle(.otherKey(t)))
        default:
            break
        }
        updateTicker()
    }

    private func updateTicker() {
        if machine.needsTicks, ticker == nil {
            let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.dispatch(self.machine.handle(.tick(ProcessInfo.processInfo.systemUptime)))
                    self.updateTicker()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !machine.needsTicks {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func dispatch(_ action: GobblKeyAction?) {
        switch action {
        case .tap:
            // While hands-free dictation runs, a tap stops it.
            if Dictation.shared.isRecording { Dictation.shared.stopHandsFree() } else { WriteAction.run() }
        case .doubleTap:
            if Dictation.shared.isRecording {
                Dictation.shared.stopHandsFree()
            } else {
                EditSession.shared.begin()
            }
        case .holdBegan(let locked):
            Dictation.shared.start(locked: locked)
        case .holdEnded:
            Dictation.shared.release()
        case .cancelled, nil:
            break
        }
    }
}
