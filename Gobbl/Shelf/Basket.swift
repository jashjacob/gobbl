import AppKit
import GobblCore
import SwiftUI

/// Shake the pointer while dragging files and a drop basket pops up right
/// there, so you don't have to drag all the way to the notch. Dropped files go
/// to the shelf; the basket leaves once the drag ends.
@MainActor
final class Basket {
    static let shared = Basket()

    let state = BasketState()
    private var panel: NotchPanel?
    private var hideTask: Task<Void, Never>?

    static var enabled: Bool { UserDefaults.standard.object(forKey: "basketEnabled") as? Bool ?? true }

    func show(at point: CGPoint) {
        guard Self.enabled else { return }
        let panel = self.panel ?? build()
        hideTask?.cancel()
        state.dropped = 0
        let size = CGSize(width: 210, height: 150)
        panel.setFrame(NSRect(x: point.x - size.width / 2, y: point.y + 24, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        PetModel.shared.send(.clipboardCopied) // Gob perks up: something's coming
    }

    /// The drag finished (dropped here, somewhere else, or cancelled).
    func dragEnded() {
        guard panel?.isVisible == true else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(self?.state.dropped ?? 0 > 0 ? 900 : 350))
            guard !Task.isCancelled, let self, !self.state.targeted else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func build() -> NotchPanel {
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 210, height: 150),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.animationBehavior = .utilityWindow
        let host = FirstMouseHostingView(rootView: BasketView(state: state))
        host.sizingOptions = []
        p.contentView = host
        panel = p
        return p
    }
}

@MainActor @Observable
final class BasketState {
    var targeted = false
    var dropped = 0
}

private struct BasketView: View {
    @Bindable var state: BasketState
    @State private var pet = PetModel.shared

    var body: some View {
        VStack(spacing: 6) {
            GobView(mood: state.dropped > 0 ? .eating : pet.mood, genome: pet.genome, stage: pet.stats.stage, size: 54,
                    hat: pet.hat, anticipating: state.targeted && state.dropped == 0)
            Text(state.dropped > 0 ? "Got \(state.dropped == 1 ? "it" : "them")! On the shelf." : "Drop here")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.targeted || state.dropped > 0 ? Palette.accent : Palette.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(state.targeted ? Palette.accent : Palette.border,
                                  style: StrokeStyle(lineWidth: 1.5, dash: state.targeted ? [] : [5, 4])))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        )
        .padding(8)
        .onDrop(of: [.fileURL], isTargeted: $state.targeted) { providers in
            state.dropped = providers.count
            ShelfModel.shared.accept(providers)
            Basket.shared.dragEnded()
            return true
        }
        .environment(\.colorScheme, .dark)
    }
}
