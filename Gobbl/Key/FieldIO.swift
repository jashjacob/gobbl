import AppKit
import ApplicationServices
import GobblCore

/// Reads the focused text field in any app and writes text back into it.
///
/// Writing tries the Accessibility API first and reads the field back to make
/// sure it landed (Chromium and Electron apps often report success and do
/// nothing). If it didn't, or the app is known not to take AX writes, it
/// pastes instead: the clipboard is saved, the text goes in marked as
/// concealed (so clipboard history skips it), ⌘V is posted, and the original
/// clipboard is put back.
@MainActor
enum FieldIO {
    struct Target {
        let element: AXUIElement
        let app: NSRunningApplication?
        let snapshot: FieldSnapshot
    }

    /// Apps whose text fields don't reliably accept Accessibility writes.
    private static let pasteFirst: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "md.obsidian", "notion.id", "com.linear",
        "com.apple.mail", "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.figma.Desktop",
    ]

    // MARK: Read

    static func capture() -> Target? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        guard let element: AXUIElement = attribute(system, kAXFocusedUIElementAttribute) else { return nil }
        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        let subrole: String = attribute(element, kAXSubroleAttribute) ?? ""
        // Never touch password fields.
        guard subrole != (kAXSecureTextFieldSubrole as String) else { return nil }
        let value: String? = attribute(element, kAXValueAttribute)
        let editable = isSettable(element, kAXValueAttribute) || ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(role)
        guard editable || value != nil else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)
        let appElement = AXUIElementCreateApplication(pid)
        let window: AXUIElement? = attribute(appElement, kAXFocusedWindowAttribute)
        let title: String = window.flatMap { attribute($0, kAXTitleAttribute) } ?? ""

        // A terminal's "value" is its whole scrollback, not a text field: only
        // a selection is used there, and nothing around it is sent.
        let terminal = isTerminal(app?.bundleIdentifier)
        let snapshot = FieldSnapshot(
            value: terminal ? "" : clean(value ?? ""),
            selection: clean(attribute(element, kAXSelectedTextAttribute) ?? ""),
            appName: app?.localizedName ?? "",
            bundleID: app?.bundleIdentifier ?? "",
            windowTitle: title,
            url: webURL(from: element),
            nearbyText: terminal ? "" : clean(window.map { nearbyText(in: $0, excluding: value ?? "") } ?? ""))
        return Target(element: element, app: app, snapshot: snapshot)
    }

    /// Text around the field: what's on screen in the focused window, capped.
    private static func nearbyText(in window: AXUIElement, excluding field: String) -> String {
        var parts: [String] = []
        var total = 0
        var visited = 0
        let deadline = Date().addingTimeInterval(0.12)
        func walk(_ el: AXUIElement, depth: Int) {
            guard visited < 600, depth < 30, total < 3000, Date() < deadline else { return }
            visited += 1
            let role: String = attribute(el, kAXRoleAttribute) ?? ""
            if ["AXMenuBar", "AXToolbar", "AXMenu", "AXButton", "AXScrollBar"].contains(role) { return }
            if role == "AXStaticText" || role == "AXHeading" {
                if let text: String = attribute(el, kAXValueAttribute), !text.isEmpty, text != field {
                    parts.append(text)
                    total += text.count
                }
            }
            let children: [AXUIElement] = attribute(el, kAXChildrenAttribute) ?? []
            for child in children { walk(child, depth: depth + 1) }
        }
        walk(window, depth: 0)
        // The end of a conversation is usually the part that matters.
        return String(parts.joined(separator: "\n").suffix(3000))
    }

    private static func webURL(from element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for _ in 0..<25 {
            guard let el = current else { return nil }
            if let url: URL = attribute(el, "AXURL") { return url.absoluteString }
            current = attribute(el, kAXParentAttribute)
        }
        return nil
    }

    // MARK: Write

    enum Placement {
        case wholeField
        case selectionOrCaret
    }

    /// Returns true when the text is in the field.
    @discardableResult
    static func write(_ text: String, into target: Target, placement: Placement) async -> Bool {
        let bundle = target.app?.bundleIdentifier ?? ""
        if !pasteFirst.contains(bundle), !isElectron(target.app), axWrite(text, into: target.element, placement: placement) {
            return true
        }
        target.app?.activate(options: [])
        return await paste(text, selectAllFirst: placement == .wholeField)
    }

    private static func axWrite(_ text: String, into element: AXUIElement, placement: Placement) -> Bool {
        let before: String = attribute(element, kAXValueAttribute) ?? ""
        if placement == .wholeField {
            // Select everything, then replace the selection: keeps the app's undo working.
            var range = CFRange(location: 0, length: (before as NSString).length)
            if let value = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            }
        }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { return false }
        // Verify: some apps report success and change nothing.
        let after: String = attribute(element, kAXValueAttribute) ?? ""
        return after != before && after.contains(text.prefix(40))
    }

    /// Paste with the user's clipboard saved and restored.
    @discardableResult
    static func paste(_ text: String, selectAllFirst: Bool = false) async -> Bool {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { copy[type] = data } }
            return copy
        } ?? []
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.writeObjects([item])

        try? await Task.sleep(for: .milliseconds(60))
        if selectAllFirst { postKey(0, command: true) } // ⌘A
        postKey(9, command: true) // ⌘V
        try? await Task.sleep(for: .milliseconds(350))

        pb.clearContents()
        let restored = saved.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
        return true
    }

    private static func postKey(_ keyCode: CGKeyCode, command: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            if command { event?.flags = .maskCommand }
            event?.post(tap: .cghidEventTap)
        }
    }

    static func isTerminal(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
                "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm"].contains(bundleID)
    }

    /// Terminals pad their text with NUL characters; drop them and trailing blanks.
    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isElectron(_ app: NSRunningApplication?) -> Bool {
        guard let url = app?.bundleURL else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
    }

    // MARK: AX helpers

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self, CFGetTypeID(value) == AXUIElementGetTypeID() { return (value as! T) }
        return value as? T
    }

    private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }
}
