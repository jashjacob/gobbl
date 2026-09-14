import Foundation

public struct ShelfItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var url: URL
    public var added: Date

    public init(id: UUID = UUID(), url: URL, added: Date = Date()) {
        self.id = id
        self.url = url
        self.added = added
    }

    public var name: String { url.lastPathComponent }
}

/// Files parked in the notch. Holds references (the files stay where they
/// are), newest first, without duplicates.
public struct Shelf: Codable, Equatable, Sendable {
    public static let capacity = 60

    public private(set) var items: [ShelfItem] = []

    public init(items: [ShelfItem] = []) {
        self.items = items
    }

    /// Adds file URLs; returns how many were new. Re-adding a file moves it to the front.
    @discardableResult
    public mutating func add(_ urls: [URL], now: Date = Date()) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let key = url.standardizedFileURL.path
            if let i = items.firstIndex(where: { $0.url.standardizedFileURL.path == key }) {
                var item = items.remove(at: i)
                item.added = now
                items.insert(item, at: 0)
            } else {
                items.insert(ShelfItem(url: url.standardizedFileURL, added: now), at: 0)
                added += 1
            }
        }
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
        return added
    }

    public mutating func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
    }

    /// After a rename or conversion in place: same item, new file.
    public mutating func replace(_ id: ShelfItem.ID, with url: URL) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].url = url.standardizedFileURL
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Drops items whose files are gone (moved or deleted since).
    public mutating func prune(exists: (URL) -> Bool) {
        items.removeAll { !exists($0.url) }
    }
}
