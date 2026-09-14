import AppKit
import AVFoundation
import GobblCore
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// One-click file tools for shelf items: convert, compress, OCR, background
/// removal, zip. Everything runs on-device. Results land next to the original
/// (or in Downloads if that folder isn't writable) and are added to the shelf.
@MainActor
enum FileActions {
    enum ImageFormat: String, CaseIterable {
        case png = "PNG", jpeg = "JPEG", heic = "HEIC"

        var type: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .heic: .heic
            }
        }
    }

    enum VideoQuality: String, CaseIterable {
        case hevc1080 = "1080p (HEVC)", p720 = "720p"

        var preset: String {
            switch self {
            case .hevc1080: AVAssetExportPresetHEVC1920x1080
            case .p720: AVAssetExportPreset1280x720
            }
        }
    }

    static func conforms(_ urls: [URL], to type: UTType) -> Bool {
        !urls.isEmpty && urls.allSatisfy { (UTType(filenameExtension: $0.pathExtension) ?? .data).conforms(to: type) }
    }

    // MARK: Actions

    static func convert(_ urls: [URL], to format: ImageFormat) {
        run("Converting…", urls) { url in
            try writeImage(from: url, as: format.type, quality: 0.9, suffix: nil)
        }
    }

    static func compressImages(_ urls: [URL]) {
        run("Compressing…", urls) { url in
            // JPEG keeps compatibility; PNGs with transparency stay PNG but get downscaled.
            let hasAlpha = (UTType(filenameExtension: url.pathExtension) ?? .data).conforms(to: .png)
            return try writeImage(from: url, as: hasAlpha ? .png : .jpeg, quality: 0.65, suffix: "compressed", maxPixel: 2560)
        }
    }

    static func imagesToPDF(_ urls: [URL]) {
        run("Making PDF…", [urls.first!]) { _ in
            let doc = PDFDocument()
            for url in urls {
                guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { continue }
                doc.insert(page, at: doc.pageCount)
            }
            let out = try destination(for: urls[0], suffix: urls.count > 1 ? "images" : nil, ext: "pdf")
            guard doc.write(to: out) else { throw ActionError("Couldn't write the PDF") }
            return out
        }
    }

    static func compressPDF(_ urls: [URL]) {
        run("Compressing PDF…", urls) { url in
            guard let doc = PDFDocument(url: url) else { throw ActionError("Couldn't open the PDF") }
            let out = try destination(for: url, suffix: "compressed", ext: "pdf")
            let ok = doc.write(to: out, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
            guard ok else { throw ActionError("Couldn't write the PDF") }
            return out
        }
    }

    static func compressVideo(_ urls: [URL], quality: VideoQuality) {
        HUDModel.shared.show(.init(symbol: "film", label: "Exporting…"), for: 60)
        Task {
            var outputs: [URL] = []
            for url in urls {
                do {
                    let asset = AVURLAsset(url: url)
                    guard let session = AVAssetExportSession(asset: asset, presetName: quality.preset) else {
                        throw ActionError("This video can't be exported at \(quality.rawValue)")
                    }
                    let out = try destination(for: url, suffix: "compressed", ext: "mp4")
                    try await session.export(to: out, as: .mp4)
                    outputs.append(out)
                } catch {
                    fail(error)
                    return
                }
            }
            finish(outputs)
        }
    }

    static func copyText(_ urls: [URL]) {
        HUDModel.shared.show(.init(symbol: "text.viewfinder", label: "Reading…"), for: 30)
        Task.detached(priority: .userInitiated) {
            let text = urls.compactMap { recognizeText(in: $0) }.joined(separator: "\n\n")
            await MainActor.run {
                guard !text.isEmpty else {
                    HUDModel.shared.show(.init(symbol: "text.viewfinder", label: "No text", tint: .red), for: 2.5)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                HUDModel.shared.show(.init(symbol: "text.viewfinder", label: "Copied", tint: Palette.accent), for: 2)
                PetModel.shared.send(.clipboardCopied)
            }
        }
    }

    static func removeBackground(_ urls: [URL]) {
        run("Cutting out…", urls) { url in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ActionError("Couldn't read the image") }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            guard let result = request.results?.first else { throw ActionError("No subject found") }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                        croppedToInstancesExtent: false)
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let cg = CIContext().createCGImage(ci, from: ci.extent) else { throw ActionError("Couldn't render the cutout") }
            let out = try destination(for: url, suffix: "cutout", ext: "png")
            try write(cg, to: out, type: .png, quality: 1)
            return out
        }
    }

    static func zip(_ urls: [URL]) {
        run("Zipping…", [urls[0]]) { _ in
            let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive"
            let out = try destination(for: urls[0], suffix: nil, ext: "zip", baseName: name)
            let parent = urls[0].deletingLastPathComponent()
            let process = Process()
            if urls.count == 1 {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, out.path]
            } else {
                // Relative names keep the archive flat; items from other folders use full paths.
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.currentDirectoryURL = parent
                process.arguments = ["-q", "-r", "-y", out.path] + urls.map {
                    $0.deletingLastPathComponent() == parent ? $0.lastPathComponent : $0.path
                }
            }
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ActionError("zip failed") }
            return out
        }
    }

    /// Asks for a new name and renames the file in place; the shelf follows it.
    static func rename(_ item: ShelfItem) {
        let alert = NSAlert()
        alert.messageText = "Rename “\(item.name)”"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: item.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        // Select the name without its extension, like Finder.
        DispatchQueue.main.async {
            let base = (item.name as NSString).deletingPathExtension
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name, !name.contains("/") else { return }
        let target = item.url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            guard !FileManager.default.fileExists(atPath: target.path) else { throw ActionError("“\(name)” already exists") }
            try FileManager.default.moveItem(at: item.url, to: target)
            ShelfModel.shared.replace(item, with: target)
            HUDModel.shared.show(.init(symbol: "pencil", label: "Renamed", tint: Palette.accent))
        } catch {
            fail(error)
        }
    }

    // MARK: Plumbing

    struct ActionError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Runs `work` per URL off the main thread, then shelves the outputs.
    private static func run(_ label: String, _ urls: [URL], work: @escaping @Sendable (URL) throws -> URL) {
        HUDModel.shared.show(.init(symbol: "wand.and.stars", label: label), for: 60)
        Task.detached(priority: .userInitiated) {
            var outputs: [URL] = []
            do {
                for url in urls { outputs.append(try work(url)) }
                await MainActor.run { finish(outputs) }
            } catch {
                await MainActor.run { fail(error) }
            }
        }
    }

    private static func finish(_ outputs: [URL]) {
        ShelfModel.shared.add(outputs)
        PetModel.shared.send(.filesDropped(outputs.count))
        HUDModel.shared.show(.init(symbol: "checkmark.circle.fill", label: "Done", tint: Palette.accent), for: 2)
    }

    private static func fail(_ error: Error) {
        HUDModel.shared.show(.init(symbol: "exclamationmark.triangle.fill", label: "Failed", tint: .red), for: 3)
        let alert = NSAlert()
        alert.messageText = "Gob couldn't do that"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// "photo (compressed).jpg" next to the original, never overwriting; Downloads if read-only.
    nonisolated static func destination(for url: URL, suffix: String?, ext: String, baseName: String? = nil) throws -> URL {
        let fm = FileManager.default
        var folder = url.deletingLastPathComponent()
        if !fm.isWritableFile(atPath: folder.path) {
            folder = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        let base = (baseName ?? url.deletingPathExtension().lastPathComponent) + (suffix.map { " (\($0))" } ?? "")
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    nonisolated private static func writeImage(from url: URL, as type: UTType, quality: Double, suffix: String?,
                                               maxPixel: Int? = nil) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ActionError("Couldn't read the image") }
        let image: CGImage?
        if let maxPixel {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                            kCGImageSourceCreateThumbnailWithTransform: true]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw ActionError("Couldn't read the image") }
        let out = try destination(for: url, suffix: suffix, ext: type.preferredFilenameExtension ?? "img")
        try write(image, to: out, type: type, quality: quality)
        return out
    }

    nonisolated private static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ActionError("Can't write \(type.localizedDescription ?? "that format")")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ActionError("Couldn't save the image") }
    }

    nonisolated private static func recognizeText(in url: URL) -> String? {
        var images: [CGImage] = []
        if (UTType(filenameExtension: url.pathExtension) ?? .data).conforms(to: .pdf), let doc = PDFDocument(url: url) {
            for i in 0..<min(doc.pageCount, 20) {
                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let thumb = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
                if let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) { images.append(cg) }
            }
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            images.append(cg)
        }
        let text = images.compactMap { image -> String? in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }
}

/// Context-menu items for whatever file tools apply to the selection.
struct FileActionsMenu: View {
    let items: [ShelfItem]

    var body: some View {
        let urls = items.map(\.url)
        if FileActions.conforms(urls, to: .image) {
            Menu("Convert Image") {
                ForEach(FileActions.ImageFormat.allCases, id: \.self) { format in
                    Button(format.rawValue) { FileActions.convert(urls, to: format) }
                }
                Button("PDF") { FileActions.imagesToPDF(urls) }
            }
            Button("Compress Image") { FileActions.compressImages(urls) }
            Button("Remove Background") { FileActions.removeBackground(urls) }
            Button("Copy Text (OCR)") { FileActions.copyText(urls) }
        }
        if FileActions.conforms(urls, to: .pdf) {
            Button("Compress PDF") { FileActions.compressPDF(urls) }
            Button("Copy Text (OCR)") { FileActions.copyText(urls) }
        }
        if FileActions.conforms(urls, to: .movie) {
            Menu("Compress Video") {
                ForEach(FileActions.VideoQuality.allCases, id: \.self) { quality in
                    Button(quality.rawValue) { FileActions.compressVideo(urls, quality: quality) }
                }
            }
        }
        Button("Compress to ZIP") { FileActions.zip(urls) }
        if items.count == 1 {
            Button("Rename…") { FileActions.rename(items[0]) }
        }
    }
}
