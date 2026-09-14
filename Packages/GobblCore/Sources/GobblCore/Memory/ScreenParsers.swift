import Foundation

/// One element from the Accessibility tree of the focused window, flattened
/// in reading order. Only what the parsers need; captured off the main thread.
public struct AXNode: Codable, Equatable, Sendable {
    public var role: String
    public var subrole: String?
    public var text: String
    public var depth: Int
    /// Horizontal position and width relative to the window (0…1), when known:
    /// chat apps put the user's own bubbles on the right.
    public var x: Double?
    public var width: Double?

    public init(role: String, subrole: String? = nil, text: String, depth: Int = 0, x: Double? = nil, width: Double? = nil) {
        self.role = role
        self.subrole = subrole
        self.text = text
        self.depth = depth
        self.x = x
        self.width = width
    }
}

extension String {
    /// Without invisible direction marks (WhatsApp prefixes names and messages with them).
    public var strippingBidiMarks: String {
        String(String.UnicodeScalarView(unicodeScalars.filter {
            !(0x200E...0x200F).contains($0.value) && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value)
        }))
    }
}

public struct ChatMessage: Equatable, Sendable {
    public var sender: String?
    public var text: String
    public var fromMe: Bool

    public init(sender: String?, text: String, fromMe: Bool) {
        self.sender = sender
        self.text = text
        self.fromMe = fromMe
    }
}

/// Readable lines from any window: text, headings, cells and text areas.
public enum GenericParser {
    static let textRoles: Set<String> = ["AXStaticText", "AXHeading", "AXTextArea", "AXCell", "AXLink"]

    public static func lines(_ nodes: [AXNode]) -> [String] {
        var out: [String] = []
        for node in nodes where textRoles.contains(node.role) && node.subrole != "AXSecureTextField" {
            for line in node.text.strippingBidiMarks.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.count >= 2 && out.last != trimmed { out.append(trimmed) }
            }
        }
        return out
    }
}

/// Turns a chat window into messages with senders. Works from what every
/// chat app shows: a sender name above a run of messages, times, delivery
/// status under the user's own messages, and own bubbles on the right.
/// Per-app role maps refine this later; this is the shared fallback.
public enum MessagingParser {
    static let timeRegex = try! NSRegularExpression(pattern: #"^(?:\d{1,2}[:.]\d{2}\s?(?:[AaPp]\.?[Mm]\.?)?|yesterday|today|just now|\d+\s?(?:m|min|h)(?: ago)?)$"#)
    static let statusWords: Set<String> = ["read", "delivered", "sent", "seen", "edited", "sending…", "sending"]

    /// `me`: names the user appears under (their own messages in Slack/Teams are left-aligned).
    public static func messages(_ nodes: [AXNode], me: Set<String> = []) -> [ChatMessage] {
        let items = nodes.filter { node in
            guard GenericParser.textRoles.contains(node.role), !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            // The chat list on the left (previews of other chats) isn't this conversation.
            if let x = node.x, let w = node.width, x + w <= 0.3 { return false }
            return true
        }
        let meLower = Set(me.map { $0.lowercased() })
        var out: [ChatMessage] = []
        var sender: String?
        var knownSenders: Set<String> = []

        for (i, node) in items.enumerated() {
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            if isTime(text) { continue }
            if statusWords.contains(lower) {
                // Delivery status only follows the user's own messages.
                if !out.isEmpty { out[out.count - 1].fromMe = true }
                continue
            }
            let next = i + 1 < items.count ? items[i + 1].text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if looksLikeName(text), i + 1 < items.count, isTime(next) || knownSenders.contains(text) || meLower.contains(lower) {
                sender = text
                knownSenders.insert(text)
                continue
            }
            let rightAligned = (node.x ?? 0) > 0.45 && (node.width ?? 1) < 0.75
            let fromMe = rightAligned || (sender.map { meLower.contains($0.lowercased()) } ?? false)
            let who = fromMe ? nil : sender
            if let last = out.last, last.sender == who, last.fromMe == fromMe, !fromMe || rightAligned {
                out[out.count - 1].text += "\n" + text
            } else {
                out.append(ChatMessage(sender: who, text: text, fromMe: fromMe))
            }
        }
        return out
    }

    static func isTime(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return timeRegex.firstMatch(in: t, options: [], range: NSRange(t.startIndex..., in: t)) != nil
    }

    /// 1–4 words, each capitalised (or non-Latin), no sentence punctuation.
    public static func looksLikeName(_ s: String) -> Bool {
        guard (2...40).contains(s.count), !s.contains(where: { ".!?:,;@/".contains($0) }), !s.contains(where: \.isNumber) else { return false }
        let words = s.split(separator: " ")
        guard (1...4).contains(words.count) else { return false }
        return words.allSatisfy { w in
            guard let first = w.first else { return false }
            return first.isUppercase || !(first.isASCII)
        }
    }

    /// Picks the reader for the app, falling back to the shared one.
    public static func parse(bundleID: String, nodes: [AXNode], me: Set<String>) -> [ChatMessage] {
        let cleaned = nodes.map { n -> AXNode in
            var n = n
            n.text = n.text.strippingBidiMarks
            return n
        }
        if bundleID == "net.whatsapp.WhatsApp", let messages = whatsApp(cleaned, me: me) { return messages }
        return messages(cleaned, me: me)
    }

    /// In a one-to-one chat, the chat is the one other person who writes in it.
    public static func chatFromSenders(_ messages: [ChatMessage]) -> String? {
        let others = Set(messages.filter { !$0.fromMe }.compactMap(\.sender))
        return others.count == 1 ? others.first : nil
    }

    static let whatsAppMessage = try! NSRegularExpression(
        pattern: #"^(?:Message|Reply|Forwarded message|Photo|Video|Voice message|Audio|Document|Sticker|GIF|Link|Contact|Location) from (.+?), (.+)$"#,
        options: [.dotMatchesLineSeparators])
    static let trailingMeta = try! NSRegularExpression(
        pattern: #",\s*(?:\d{1,2}[:.]\d{2}\s?(?:[AaPp]\.?[Mm]\.?)?|Read|Delivered|Sent|Seen|Edited|Pending|Starred|Today|Yesterday|(?:Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day|\d{1,2}/\d{1,2}/\d{2,4}|\d{1,2} [A-Z][a-z]{2,8}(?: \d{4})?)\s*$"#)

    /// WhatsApp (Mac Catalyst) exposes each message as one element:
    /// "Message from Samar Mustafa, can you send the deck?, 6:02 PM". Chat-list
    /// previews don't have that shape and are left out. Nil when nothing matched.
    static func whatsApp(_ nodes: [AXNode], me: Set<String>) -> [ChatMessage]? {
        let mine = Set(me.map { EntityRules.normalize($0) } + ["you"])
        var out: [ChatMessage] = []
        for node in nodes {
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = text as NSString
            guard let m = whatsAppMessage.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            let sender = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            var body = ns.substring(with: m.range(at: 2))
            // Peel time, date and delivery status off the end.
            while let meta = trailingMeta.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)) {
                body = (body as NSString).substring(to: meta.range.location)
            }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let fromMe = mine.contains(EntityRules.normalize(sender))
            out.append(ChatMessage(sender: fromMe ? nil : sender, text: body, fromMe: fromMe))
        }
        return out.isEmpty ? nil : out
    }

    /// The chat's name from the window title ("general (Channel) - Acme - Slack", "Samar — WhatsApp").
    public static func chatName(windowTitle: String, appName: String) -> String? {
        var t = windowTitle
        for sep in [" - ", " — ", " | "] {
            if let range = t.range(of: sep + appName, options: [.caseInsensitive, .backwards]) { t = String(t[..<range.lowerBound]) }
        }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.caseInsensitiveCompare(appName) == .orderedSame { return nil }
        if let first = t.components(separatedBy: " - ").first, t.contains(" - ") { return first.trimmingCharacters(in: .whitespaces) }
        return t
    }
}
