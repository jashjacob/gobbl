import AppKit
import GobblCore
import Observation
import QuickLookThumbnailing

/// The shelf, persisted in UserDefaults. Files are referenced, not copied.
@MainActor @Observable
final class ShelfModel {
    static let shared = ShelfModel()

    private(set) var shelf: Shelf
    /// Bumped when a Quick Look thumbnail arrives, so tiles redraw.
    private(set) var thumbnailsVersion = 0

    @ObservationIgnored private let thumbnails = NSCache<NSURL, NSImage>()
    @ObservationIgnored private var pending: Set<URL> = []
    private static let key = "shelf"

    private init() {
        var shelf = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Shelf.self, from: $0) } ?? Shelf()
        shelf.prune { FileManager.default.fileExists(atPath: $0.path) }
        self.shelf = shelf
    }

    var items: [ShelfItem] { shelf.items }

    /// Loads file URLs from a drop, shelves them and feeds Gob.
    func accept(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let box = URLBox()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                // A dropped .gobskin is something to wear, not to shelve.
                let skins = box.urls.filter { $0.pathExtension.lowercased() == PetSkin.fileExtension }
                skins.forEach { SkinLibrary.shared.install(from: $0) }
                let urls = box.urls.filter { !skins.contains($0) }
                guard let self, !urls.isEmpty else { return }
                self.add(urls)
                // Re-dropping a shelved file still earns a chomp.
                PetModel.shared.send(.filesDropped(urls.count))
            }
        }
    }

    func add(_ urls: [URL]) {
        shelf.add(urls)
        save()
    }

    #if DEBUG
    /// `--demo`: sample files for screenshots, shown but never saved over the real shelf.
    func setDemo(_ urls: [URL]) {
        var demo = Shelf()
        demo.add(urls)
        shelf = demo
    }
    #endif

    func remove(_ item: ShelfItem) {
        shelf.remove(item.id)
        save()
    }

    func replace(_ item: ShelfItem, with url: URL) {
        shelf.replace(item.id, with: url)
        save()
    }

    func removeAll() {
        shelf.removeAll()
        save()
    }

    // MARK: Actions

    func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }

    func reveal(_ items: [ShelfItem]) { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url)) }

    func quickLook(_ item: ShelfItem) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", item.url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
        HUDModel.shared.show(.init(symbol: "doc.on.clipboard.fill", label: "Copied"))
    }

    func airDrop(_ items: [ShelfItem]) {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items.map(\.url))
    }

    func share(_ items: [ShelfItem]) {
        Share.show(items.map(\.url))
    }

    // MARK: Thumbnails

    /// A Quick Look thumbnail when one is ready, else the file's icon.
    func icon(for item: ShelfItem) -> NSImage {
        _ = thumbnailsVersion
        if let cached = thumbnails.object(forKey: item.url as NSURL) { return cached }
        requestThumbnail(item.url)
        return NSWorkspace.shared.icon(forFile: item.url.path)
    }

    private func requestThumbnail(_ url: URL) {
        guard !pending.contains(url) else { return }
        pending.insert(url)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 104, height: 104),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            let image = rep?.nsImage
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let image else { return }
                    self.thumbnails.setObject(image, forKey: url as NSURL)
                    self.thumbnailsVersion += 1
                }
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(shelf), forKey: Self.key)
    }
}

/// The system share menu, anchored to the open notch.
@MainActor
enum Share {
    static func show(_ items: [Any]) {
        guard !items.isEmpty else { return }
        guard let view = NotchController.shared.anchorView() else {
            if let urls = items as? [URL] { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            return
        }
        let picker = NSSharingServicePicker(items: items)
        let rect = NSRect(x: view.bounds.midX - 1, y: view.bounds.maxY - 60, width: 2, height: 2)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }
}

/// Collects URLs from NSItemProvider callbacks, which arrive on arbitrary queues.
private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
