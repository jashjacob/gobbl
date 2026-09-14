import AppKit
import AVFoundation
import GobblCore
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// Shareable clips of Gob. Two kinds:
/// - Scenes: short scripted moments rendered frame by frame from our own
///   views — 1080×1080 MP4 plus a GIF, no permissions needed.
/// - Record My Notch: a real screen recording of the notch area.
@MainActor
enum ClipStudio {
    enum Scene: String, CaseIterable, Identifiable {
        case snack, dance, pet, agent, levelUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .snack: "Snack time"
            case .dance: "Dance party"
            case .pet: "Pet me"
            case .agent: "AI agent done"
            case .levelUp: "Level up"
            }
        }

        var caption: String {
            switch self {
            case .snack: "It eats your files."
            case .dance: "It dances to your music."
            case .pet: "Pet it. It loves you back."
            case .agent: "It cheers when your AI agent finishes."
            case .levelUp: "Feed it. Watch it grow."
            }
        }

        static let duration = 6.0

        /// What Gob does at time t.
        func beat(at t: Double, level: Int) -> Beat {
            switch self {
            case .snack:
                if t < 0.5 { return Beat(mood: .curious, look: 1) }
                if t < 1.2 { return Beat(mood: .curious, open: true, look: 0.6, file: (t - 0.5) / 0.7) }
                if t < 2.8 { return Beat(mood: .eating) }
                if t < 3.5 { return Beat(mood: .happy) }
                if t < 4.3 { return Beat(mood: .burping) }
                return Beat(mood: .love)
            case .dance:
                return Beat(mood: .dancing, chip: "♪  Now playing")
            case .pet:
                if t < 1.2 { return Beat(mood: .curious, look: -0.6, hand: t / 1.2) }
                if t < 4.5 { return Beat(mood: .love, hand: 1 + 0.1 * sin(t * 12)) }
                return Beat(mood: .happy)
            case .agent:
                if t < 1.6 { return Beat(mood: .thinking, chip: "Claude is thinking…") }
                if t < 3.6 { return Beat(mood: .working, chip: "Claude is coding…") }
                return Beat(mood: .celebrating, chip: "✓  Task done")
            case .levelUp:
                if t < 1 { return Beat(mood: .idle) }
                return Beat(mood: .celebrating, chip: "Level \(level + 1)!")
            }
        }
    }

    struct Beat {
        var mood: Mood
        var open = false
        var look: CGFloat = 0
        var chip: String?
        /// 0–1 while a file flies into Gob's mouth.
        var file: Double?
        /// 0–1 while a hand reaches in to pet.
        var hand: Double?
    }

    // MARK: Scenes

    static func export(_ scene: Scene) {
        HUDModel.shared.show(.init(symbol: "film.stack", label: "Rendering…"), for: 30)
        Task {
            do {
                let pet = PetModel.shared
                let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                let base = folder.appendingPathComponent("\(pet.name) – \(scene.title)")
                let mp4 = try unique(base.appendingPathExtension("mp4"))
                let gif = try unique(base.appendingPathExtension("gif"))
                try await render(scene, video: mp4, gif: gif)
                PetModel.shared.send(.celebrate)
                HUDModel.shared.show(.init(symbol: "film.fill", label: "Saved", tint: Palette.accent), for: 2)
                Share.show([mp4, gif])
            } catch {
                HUDModel.shared.show(.init(symbol: "exclamationmark.triangle.fill", label: "Failed", tint: .red), for: 3)
            }
        }
    }

    /// Renders 30 fps 1080×1080 H.264 and a 15 fps 540×540 looping GIF in one pass.
    static func render(_ scene: Scene, video: URL, gif: URL) async throws {
        let fps = 30
        let frames = Int(Scene.duration * Double(fps))
        let side = 1080

        let writer = try AVAssetWriter(outputURL: video, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: side,
            AVVideoHeightKey: side,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: side,
            kCVPixelBufferHeightKey as String: side,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        guard let gifDest = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, frames / 2, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(gifDest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let gifFrame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 2.0 / Double(fps)]] as CFDictionary

        let pet = PetModel.shared
        for i in 0..<frames {
            let t = Double(i) / Double(fps)
            let view = ClipFrame(scene: scene, t: t, genome: pet.genome, stage: pet.stats.stage, level: pet.stats.level,
                                 hat: pet.hat, name: pet.name)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { continue }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            if let pool = adaptor.pixelBufferPool, let buffer = pixelBuffer(from: image, pool: pool) {
                adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            }
            if i.isMultiple(of: 2), let small = downscale(image, to: side / 2) {
                CGImageDestinationAddImage(gifDest, small, gifFrame)
            }
            if i.isMultiple(of: 6) { await Task.yield() }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        guard CGImageDestinationFinalize(gifDest) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer),
                                  height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        return buffer
    }

    private static func downscale(_ image: CGImage, to side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }

    static func unique(_ url: URL) throws -> URL {
        var candidate = url
        var n = 2
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}

/// One frame of a scene: the top of a Mac screen with its notch, Gob hanging
/// out underneath, a caption and the URL.
struct ClipFrame: View {
    let scene: ClipStudio.Scene
    let t: Double
    let genome: PetGenome
    let stage: Int
    let level: Int
    let hat: Hat
    let name: String

    var body: some View {
        let beat = scene.beat(at: t, level: level)
        let hue = genome.species.hue
        ZStack(alignment: .top) {
            Color(hex: 0x0B0B0E)
            RadialGradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 0.9).opacity(0.4), .clear],
                           center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 320)
            // Menu bar strip.
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 26)
            HStack {
                Text("Finder   File   Edit   View").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("9:41").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18)
            .frame(height: 26)
            // The notch, grown open, with Gob inside.
            NotchShape(flare: 12, radius: 40, attached: true)
                .fill(Color.black)
                .frame(width: 330, height: 280)
                .overlay(alignment: .bottom) {
                    // +0.5 s so the first frame (the GIF's thumbnail) isn't mid-blink.
                    GobView(mood: beat.mood, genome: genome, stage: stage, size: 220, hat: hat,
                            anticipating: beat.open, time: t + 0.5, look: { beat.look })
                        .padding(.bottom, 14)
                }
                .overlay(alignment: .topTrailing) {
                    if let chip = beat.chip {
                        Text(chip)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Palette.accent))
                            .offset(x: 70, y: 40)
                    }
                }
            if let f = beat.file {
                // A document flying into Gob's mouth.
                Image(systemName: "doc.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white)
                    .scaleEffect(1 - f * 0.6)
                    .rotationEffect(.degrees(f * 200))
                    .position(x: 470 - f * 200, y: 110 + f * 110)
            }
            if let h = beat.hand {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
                    .position(x: 60 + min(h, 1) * 170, y: 330 - min(h, 1) * 90)
            }
            VStack(spacing: 8) {
                Spacer()
                Text(scene.caption)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Text("\(name) the \(genome.species.displayName) · gobbl.xeve.io")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hue: hue, saturation: 0.45, brightness: 1))
                    .padding(.bottom, 34)
            }
        }
        .frame(width: 540, height: 540)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Record My Notch

/// A 6-second screen recording of the area around the notch (ScreenCaptureKit;
/// asks for Screen Recording the first time). A 3-second countdown gives time
/// to hover the notch and play with Gob.
@MainActor
final class NotchRecorder {
    static let shared = NotchRecorder()

    private(set) var isRecording = false
    private var stream: SCStream?
    private var sink: RecordingSink?

    func record(seconds: Double = 6) {
        guard !isRecording else { return }
        isRecording = true
        Task {
            defer { isRecording = false }
            do {
                for n in (1...3).reversed() {
                    HUDModel.shared.show(.init(symbol: "record.circle", label: "\(n)", tint: .red), for: 1.1)
                    try await Task.sleep(for: .seconds(1))
                }
                let url = try await capture(seconds: seconds)
                HUDModel.shared.show(.init(symbol: "film.fill", label: "Saved", tint: Palette.accent), for: 2)
                Share.show([url])
            } catch {
                HUDModel.shared.show(.init(symbol: "exclamationmark.triangle.fill", label: "Failed", tint: .red), for: 3)
                let alert = NSAlert()
                alert.messageText = "Couldn't record the notch"
                alert.informativeText = "Gobbl needs Screen Recording permission: System Settings → Privacy & Security → Screen & System Audio Recording.\n\n\(error.localizedDescription)"
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func capture(seconds: Double) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen, let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CocoaError(.featureUnsupported)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Display-local points, top-left origin: a 720×300 box centred on the notch.
        let w: CGFloat = 720, h: CGFloat = 300
        config.sourceRect = CGRect(x: screen.frame.width / 2 - w / 2, y: 0, width: w, height: h)
        config.width = Int(w * 2)
        config.height = Int(h * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let url = try ClipStudio.unique(folder.appendingPathComponent("\(PetModel.shared.name) in my notch.mp4"))
        let sink = try RecordingSink(url: url, width: config.width, height: config.height)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        self.sink = sink
        self.stream = stream
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        self.stream = nil
        try await sink.finish()
        self.sink = nil
        return url
    }
}

/// Receives ScreenCaptureKit frames on its own queue and writes them to an MP4.
private final class RecordingSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.xeve.gobbl.recording")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false

    init(url: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }

    func finish() async throws {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { done.resume() } // drain frames already queued
        }
        guard started else { throw CocoaError(.fileWriteUnknown) }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
