import AppKit
import ApplicationServices
import GobblCore

/// The focused window of one app, read through Accessibility in a single
/// bounded walk. Thread-safe: runs on the capture queue, never the main thread.
struct WindowSnapshot {
    let title: String
    let url: String?
    let nodes: [AXNode]
    let truncated: Bool
    let elapsed: TimeInterval
}

enum AXSnapshot {
    /// Chrome and controls: no content worth remembering, and big subtrees.
    private static let skipRoles: Set<String> = [
        "AXMenuBar", "AXMenu", "AXMenuItem", "AXToolbar", "AXScrollBar", "AXButton", "AXPopUpButton", "AXMenuButton",
        "AXImage", "AXCheckBox", "AXRadioButton", "AXSlider", "AXIncrementor", "AXColorWell", "AXDisclosureTriangle",
    ]
    private static let textRoles: Set<String> = ["AXStaticText", "AXHeading", "AXTextArea", "AXTextField", "AXCell", "AXLink"]

    /// - withGeometry: record each text's horizontal position (chat bubbles).
    /// - skipEditable: leave out text fields and areas (a chat's compose box).
    static func focusedWindow(pid: pid_t, withGeometry: Bool, skipEditable: Bool,
                              maxNodes: Int = 2000, maxDepth: Int = 40, budget: TimeInterval = 0.15) -> WindowSnapshot? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // The focused window, else the main one, else the first (apps in the
        // background don't always report a focused window).
        guard let window: AXUIElement = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
            ?? firstWindow(app) else { return nil }
        let title = string(window, kAXTitleAttribute) ?? ""
        var frame = CGRect.zero
        if withGeometry, let origin = point(of: window), let size = size(of: window) { frame = CGRect(origin: origin, size: size) }

        var attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXTitleAttribute,
                          kAXDescriptionAttribute, kAXChildrenAttribute] as [CFString]
        if withGeometry { attributes += [kAXPositionAttribute, kAXSizeAttribute] as [CFString] }

        let start = Date()
        let deadline = start.addingTimeInterval(budget)
        var nodes: [AXNode] = []
        var url: String?
        var visited = 0
        var truncated = false

        func walk(_ el: AXUIElement, depth: Int) {
            guard visited < maxNodes, depth <= maxDepth, Date() < deadline else {
                truncated = true
                return
            }
            visited += 1
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(el, attributes as CFArray, [], &raw) == .success,
                  let values = raw as? [AnyObject], values.count >= 6 else { return }
            func text(_ i: Int) -> String? {
                guard let s = values[i] as? String, !s.isEmpty else { return nil }
                return s
            }
            let role = text(0) ?? ""
            let subrole = text(1)
            if skipRoles.contains(role) || subrole == (kAXSecureTextFieldSubrole as String) { return }
            if role == "AXWebArea", url == nil, let u = urlValue(el) { url = u }
            if textRoles.contains(role) {
                let editable = role == "AXTextArea" || role == "AXTextField"
                if !(editable && skipEditable), let value = text(2) ?? text(3) ?? text(4) {
                    var node = AXNode(role: role, subrole: subrole, text: String(value.prefix(4000)), depth: depth)
                    if withGeometry, frame.width > 0, values.count >= 8,
                       let p = axPoint(values[6]), let s = axSize(values[7]) {
                        node.x = Double((p.x - frame.minX) / frame.width)
                        node.width = Double(s.width / frame.width)
                    }
                    nodes.append(node)
                }
                if role == "AXStaticText" { return } // a leaf in practice
            }
            guard let children = values[5] as? [AnyObject] else { return }
            for child in children where CFGetTypeID(child) == AXUIElementGetTypeID() {
                walk(child as! AXUIElement, depth: depth + 1)
            }
        }
        walk(window, depth: 0)
        return WindowSnapshot(title: title, url: url, nodes: nodes, truncated: truncated, elapsed: Date().timeIntervalSince(start))
    }

    /// Electron and Chromium apps build their tree only when asked. This is the
    /// flag that doesn't break window managers (unlike AXEnhancedUserInterface).
    static func enableManualAccessibility(pid: pid_t) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: Helpers

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func firstWindow(_ app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AnyObject], let first = windows.first,
              CFGetTypeID(first) == AXUIElementGetTypeID() else { return nil }
        return (first as! AXUIElement)
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func urlValue(_ el: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXURL" as CFString, &value) == .success else { return nil }
        return (value as? URL)?.absoluteString
    }

    private static func point(of el: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &value) == .success, let value else { return nil }
        return axPoint(value)
    }

    private static func size(of el: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &value) == .success, let value else { return nil }
        return axSize(value)
    }

    private static func axPoint(_ value: AnyObject) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func axSize(_ value: AnyObject) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
    }
}
