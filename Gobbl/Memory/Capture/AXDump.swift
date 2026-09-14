#if DEBUG
import AppKit
import GobblCore

/// `--ax-dump <bundleID>`: reads that app's focused window once and prints the
/// nodes, what the parsers make of them, and the redacted result, as JSON.
/// Stores nothing. Used to check capture per app and to record test fixtures.
enum AXDump {
    static func run(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            print("{\"error\": \"\(bundleID) is not running\"}")
            exit(1)
        }
        let kind = CaptureRules.kind(of: bundleID)
        if kind == .messaging || kind == .browser || app.bundleURL.map({ FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) }) == true {
            AXSnapshot.enableManualAccessibility(pid: app.processIdentifier)
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard let snap = AXSnapshot.focusedWindow(pid: app.processIdentifier, withGeometry: kind == .messaging,
                                                  skipEditable: kind == .messaging || kind == .mail,
                                                  budget: kind == .messaging ? 0.4 : 0.15) else {
            print("{\"error\": \"no window\", \"accessibilityTrusted\": \(AXIsProcessTrusted())}")
            exit(1)
        }
        var result: [String: Any] = [
            "app": app.localizedName ?? bundleID, "kind": kind.rawValue, "title": snap.title, "url": snap.url ?? NSNull(),
            "private": CaptureRules.isPrivateWindow(title: snap.title), "nodes": snap.nodes.count,
            "elapsedMs": Int(snap.elapsed * 1000), "truncated": snap.truncated,
        ]
        if kind == .messaging {
            let messages = MessagingParser.parse(bundleID: bundleID, nodes: snap.nodes, me: Set(MemoryModel.myNames))
            result["chat"] = MessagingParser.chatName(windowTitle: snap.title.strippingBidiMarks, appName: MemoryModel.cleanName(app.localizedName ?? ""))
                ?? MessagingParser.chatFromSenders(messages) ?? NSNull()
            result["senders"] = Array(Set(messages.compactMap(\.sender))).map(shape)
            result["fromMe"] = messages.filter(\.fromMe).count
            result["messages"] = messages.map {
                ["sender": $0.sender ?? NSNull(), "fromMe": $0.fromMe, "text": Redactor.redact($0.text)] as [String: Any]
            }
        } else {
            result["lines"] = GenericParser.lines(snap.nodes).map(Redactor.redact)
        }
        if CommandLine.arguments.contains("--raw") {
            result["raw"] = snap.nodes.map { ["role": $0.role, "subrole": $0.subrole ?? NSNull(), "text": $0.text,
                                              "depth": $0.depth, "x": $0.x ?? NSNull(), "width": $0.width ?? NSNull()] as [String: Any] }
        }
        if CommandLine.arguments.contains("--shape") {
            // Layout only: text becomes a pattern ("Samar Mustafa" → "Aaaaa Aaaaaaa (13)"), so a
            // window's structure can be studied without reading anyone's messages.
            result.removeValue(forKey: "lines")
            result.removeValue(forKey: "messages")
            result["title"] = shape(snap.title)
            result["chat"] = (result["chat"] as? String).map(shape) ?? NSNull()
            result["shape"] = snap.nodes.map { n -> String in
                let x = n.x.map { String(format: "%.2f", $0) } ?? "-"
                let w = n.width.map { String(format: "%.2f", $0) } ?? "-"
                return "\(String(repeating: "  ", count: min(n.depth, 20)))\(n.role)\(n.subrole.map { "/\($0)" } ?? "") x=\(x) w=\(w) \"\(shape(n.text))\""
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .withoutEscapingSlashes]) {
            print(String(decoding: data, as: UTF8.self))
        }
        fflush(stdout)
        exit(0)
    }

    /// Letters become a/A, digits 9, punctuation and spaces stay; long text is cut.
    static func shape(_ s: String) -> String {
        let mapped = s.prefix(28).map { ch -> Character in
            if ch.isUppercase { return "A" }
            if ch.isLetter { return "a" }
            if ch.isNumber { return "9" }
            return ch.isNewline ? "/" : ch
        }
        return String(mapped) + (s.count > 28 ? "… (\(s.count))" : " (\(s.count))")
    }
}
#endif
