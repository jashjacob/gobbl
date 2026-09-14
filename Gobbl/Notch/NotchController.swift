import AppKit
import GobblCore
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, chat, shelf, clipboard, agents, tools
    /// Edit mode (double-tap the Gobbl key). Not in the tab bar.
    case edit

    var id: String { rawValue }

    /// The tabs shown in the bar.
    static let bar: [NotchTab] = [.home, .chat, .shelf, .clipboard, .agents, .tools]

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .chat: "bubble.left.fill"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .agents: "sparkles"
        case .tools: "timer"
        case .edit: "pencil.and.scribble"
        }
    }

    var title: String { rawValue.capitalized }
}

@MainActor @Observable
final class NotchState {
    var expanded = false
    var geometry = NotchGeometry()
    var dropTargeted = false
    var tab: NotchTab = .home
    @ObservationIgnored weak var window: NotchWindow?
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Buttons work on the first click without activating Gobbl.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

extension ScreenMetrics {
    @MainActor init(_ screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top,
                  auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
                  auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width)
    }
}

/// The overlay on one display: a borderless, non-activating panel above the
/// menu bar. It passes clicks through everywhere except over the visible shape.
///
/// Opened by hover, it closes when the pointer leaves. Opened by a click or a
/// shortcut it is "sticky": it stays until a click outside, Esc, or an action.
@MainActor
final class NotchWindow {
    let displayID: CGDirectDisplayID
    let state = NotchState()
    private let panel: NotchPanel
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var sticky = false
    /// The app that was frontmost when we took keyboard focus, to hand it back.
    private var previousApp: NSRunningApplication?
    /// DEBUG `--expand`: stays open regardless of the pointer.
    var pinned = false

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        panel = p
        let host = FirstMouseHostingView(rootView: NotchView(state: state))
        host.sizingOptions = []
        p.contentView = host
        state.window = self
    }

    func layout(on screen: NSScreen) {
        state.geometry = NotchGeometry(metrics: ScreenMetrics(screen))
        panel.setFrame(state.geometry.panelFrame, display: true)
    }

    var isVisible: Bool { panel.isVisible }
    var contentView: NSView? { panel.contentView }

    func show() {
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
        setExpanded(false)
    }

    func teardown() {
        hoverTask?.cancel()
        collapseTask?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    func isNear(_ p: CGPoint) -> Bool {
        panel.isVisible && state.geometry.contains(p, expanded: state.expanded, slop: 40)
    }

    func contains(_ p: CGPoint) -> Bool {
        panel.isVisible && state.geometry.contains(p, expanded: state.expanded)
    }

    // MARK: Open / close

    func toggle() {
        state.expanded ? close() : open(tab: nil, focus: false)
    }

    func open(tab: NotchTab?, focus: Bool) {
        if let tab { state.tab = tab }
        show()
        sticky = true
        setExpanded(true)
        if focus {
            previousApp = NSWorkspace.shared.frontmostApplication
            panel.makeKey()
        }
    }

    func close() {
        sticky = false
        setExpanded(false)
    }

    func mouseDown(at p: CGPoint) {
        guard state.expanded, !pinned, !state.geometry.contains(p, expanded: true) else { return }
        close()
    }

    func mouseMoved(to p: CGPoint, draggingFiles: Bool, expandOnHover: Bool) {
        guard panel.isVisible else { return }
        let inside = state.geometry.contains(p, expanded: state.expanded)
        // Clicks outside the shape go straight through to whatever is underneath.
        panel.ignoresMouseEvents = !inside
        if inside {
            collapseTask?.cancel()
            collapseTask = nil
            guard !state.expanded, hoverTask == nil, expandOnHover || draggingFiles else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(draggingFiles ? 60 : 150))
                guard let self, !Task.isCancelled else { return }
                self.hoverTask = nil
                if self.state.geometry.contains(NSEvent.mouseLocation, expanded: false) { self.setExpanded(true) }
            }
        } else {
            hoverTask?.cancel()
            hoverTask = nil
            guard state.expanded, !pinned, !sticky, collapseTask == nil else { return }
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(260))
                guard let self, !Task.isCancelled else { return }
                self.collapseTask = nil
                if !self.sticky, !self.state.dropTargeted,
                   !self.state.geometry.contains(NSEvent.mouseLocation, expanded: true) {
                    self.setExpanded(false)
                }
            }
        }
    }

    func setExpanded(_ on: Bool) {
        guard state.expanded != on else { return }
        state.expanded = on
        panel.ignoresMouseEvents = !state.geometry.contains(NSEvent.mouseLocation, expanded: on)
        guard !on else { return }
        sticky = false
        if panel.isKeyWindow, let previousApp, !previousApp.isTerminated {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }
}

/// Owns one NotchWindow per display (or just the notched one), a single set of
/// mouse monitors shared by all of them, and full-screen hiding.
@MainActor
final class NotchController {
    static let shared = NotchController()

    private var windows: [CGDirectDisplayID: NotchWindow] = [:]
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var applied: Settings?
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var cursorNear = false
    private var shake = ShakeDetector()
    private var started = false

    struct Settings: Equatable {
        var enabled: Bool
        var allDisplays: Bool
        var expandOnHover: Bool
    }

    private var settings: Settings {
        let d = UserDefaults.standard
        return Settings(enabled: d.object(forKey: "notchEnabled") as? Bool ?? true,
                        allDisplays: d.bool(forKey: "notchAllDisplays"),
                        expandOnHover: d.object(forKey: "notchExpandOnHover") as? Bool ?? true)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(force: true) }
        })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleFullScreenCheck() }
            })
        }
        installMonitors()
        apply(force: true)
    }

    /// Re-reads settings; cheap when nothing relevant changed.
    private func apply(force: Bool = false) {
        let s = settings
        guard force || s != applied else { return }
        applied = s
        rebuild(s)
    }

    private func rebuild(_ s: Settings) {
        guard s.enabled else {
            windows.values.forEach { $0.teardown() }
            windows.removeAll()
            return
        }
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let targets = s.allDisplays ? NSScreen.screens : [notched ?? NSScreen.main].compactMap { $0 }
        let ids = Set(targets.compactMap(\.displayID))
        for (id, window) in windows where !ids.contains(id) {
            window.teardown()
            windows[id] = nil
        }
        for screen in targets {
            guard let id = screen.displayID else { continue }
            let window = windows[id] ?? NotchWindow(displayID: id)
            windows[id] = window
            window.layout(on: screen)
        }
        updateFullScreen()
    }

    /// Opens (sticky, with keyboard focus) on the display under the pointer.
    func open(tab: NotchTab, focus: Bool = true) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let target = screen?.displayID.flatMap { windows[$0] } ?? windows.values.first
        target?.open(tab: tab, focus: focus)
    }

    func closeAll() {
        windows.values.forEach { $0.close() }
    }

    /// An open notch's view, to anchor share menus to.
    func anchorView() -> NSView? {
        (windows.values.first { $0.state.expanded } ?? windows.values.first { $0.isVisible })?.contentView
    }

    func debugExpand() {
        for window in windows.values {
            window.pinned = true
            window.setExpanded(true)
        }
    }

    // MARK: Input

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(local) }
        // Esc closes an open notch (our panel only gets keys while it is key).
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closeAll() }
            return nil
        }) { monitors.append(keys) }
    }

    private func handle(_ event: NSEvent) {
        let p = NSEvent.mouseLocation
        if event.type == .leftMouseDown {
            dragBaseline = NSPasteboard(name: .drag).changeCount
            windows.values.forEach { $0.mouseDown(at: p) }
        }
        if event.type == .leftMouseUp {
            Basket.shared.dragEnded()
            return
        }
        // A drag that wrote to the drag pasteboard is carrying something (files, text…).
        let dragging = event.type == .leftMouseDragged && NSPasteboard(name: .drag).changeCount != dragBaseline
        if shake.feed(x: p.x, time: event.timestamp) {
            if dragging {
                Basket.shared.show(at: p)
            } else if windows.values.contains(where: { $0.isVisible && hypot(p.x - $0.state.geometry.centerX, p.y - $0.state.geometry.screenTop) < 320 }) {
                PetModel.shared.send(.shaken)
            }
        }
        let hover = applied?.expandOnHover ?? true
        var near: NotchWindow?
        for window in windows.values {
            window.mouseMoved(to: p, draggingFiles: dragging, expandOnHover: hover)
            if near == nil, window.isNear(p) { near = window }
        }
        let pet = PetModel.shared
        pet.wakeIfSleeping()
        // Gob's eyes follow the pointer anywhere on screen, measured from the notch.
        if let anchor = near ?? windows.values.first(where: \.isVisible) {
            let g = anchor.state.geometry
            pet.pointerMoved(look: max(-1, min(1, (p.x - g.centerX) / 500)),
                             lookY: max(-1, min(1, (g.screenTop - g.barHeight - p.y) / 450)))
        }
        if (near != nil) != cursorNear {
            cursorNear = near != nil
            pet.send(.cursorNear(cursorNear))
        }
    }

    // MARK: Full screen

    private func scheduleFullScreenCheck() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.updateFullScreen()
        }
    }

    private func updateFullScreen() {
        for (id, window) in windows {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { continue }
            if Self.frontAppIsFullScreen(on: screen) { window.hide() } else { window.show() }
        }
    }

    /// The menu bar hides for full-screen apps; so do we. Detected as a
    /// layer-0 window of the frontmost app covering the whole screen.
    private static func frontAppIsFullScreen(on screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // CGWindow bounds are top-left based, relative to the primary display.
        let target = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict) else { return false }
            return rect.integral == target.integral
        }
    }
}
