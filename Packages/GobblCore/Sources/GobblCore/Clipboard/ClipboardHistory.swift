import Foundation

public struct ClipItem: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text, link, image, file
    }

    public var id: UUID
    public var kind: Kind
    /// The text or URL; file paths joined by newlines; or, for images, the stored PNG's file name.
    public var text: String
    /// Images: content hash, so the same picture copied twice is one entry.
    public var digest: String?
    public var date: Date
    public var pinned: Bool
    public var sourceApp: String?

    public init(id: UUID = UUID(), kind: Kind, text: String, digest: String? = nil, date: Date = Date(),
                pinned: Bool = false, sourceApp: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.digest = digest
        self.date = date
        self.pinned = pinned
        self.sourceApp = sourceApp
    }

    public var dedupeKey: String { "\(kind.rawValue):\(digest ?? text)" }

    /// One line for the list.
    public var preview: String {
        switch kind {
        case .image: return "Image"
        case .file:
            let names = text.split(separator: "\n").map { ($0 as NSString).lastPathComponent }
            return names.count > 1 ? "\(names[0]) + \(names.count - 1) more" : names.first ?? ""
        case .text, .link:
            let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return String(collapsed.prefix(200))
        }
    }
}

/// Newest first. Copying something already in the history moves it to the
/// top (keeping its pin); pinned items are never evicted.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public static let defaultLimit = 200

    public private(set) var items: [ClipItem] = []
    public var limit: Int

    public init(items: [ClipItem] = [], limit: Int = defaultLimit) {
        self.items = items
        self.limit = limit
    }

    public func item(matching dedupeKey: String) -> ClipItem? {
        items.first { $0.dedupeKey == dedupeKey }
    }

    /// Records a copy; returns evicted items (so the caller can delete stored images).
    @discardableResult
    public mutating func record(_ item: ClipItem) -> [ClipItem] {
        var item = item
        if let i = items.firstIndex(where: { $0.dedupeKey == item.dedupeKey }) {
            let old = items.remove(at: i)
            item.id = old.id
            item.pinned = old.pinned
        }
        items.insert(item, at: 0)
        var evicted: [ClipItem] = []
        while items.count > limit, let i = items.lastIndex(where: { !$0.pinned }) {
            evicted.append(items.remove(at: i))
        }
        return evicted
    }

    public mutating func togglePin(_ id: ClipItem.ID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
    }

    @discardableResult
    public mutating func remove(_ id: ClipItem.ID) -> ClipItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    /// Removes everything that isn't pinned; returns what was removed.
    @discardableResult
    public mutating func clearUnpinned() -> [ClipItem] {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        return removed
    }

    /// Pinned first, then by recency; case-insensitive substring search.
    public func filtered(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = q.isEmpty ? items : items.filter {
            $0.kind == .image ? "image".localizedCaseInsensitiveContains(q) : $0.text.localizedCaseInsensitiveContains(q)
        }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }
}
