import GobblCore
import SwiftUI

/// The pet: a little computer with a face on its screen. Three eras
/// (`PetCharacter`), all generic archetypes rather than any real product.
/// Every Mood gets a pose; while an AI agent codes the screen fills with
/// Matrix rain, while it thinks the face ponders. Stand-in for the Rive art —
/// swapping the renderer later doesn't change any call site.
struct GobView: View {
    var mood: Mood
    var genome: PetGenome
    var stage: Int
    var size: CGFloat
    var hat: Hat = .none
    /// nil: whatever the user picked (PetModel.character).
    var character: PetCharacter? = nil
    /// nil: the pet's current skin (none means species colours).
    var skin: PetSkin? = nil
    /// Mouth open, waiting: a file is being dragged over the notch.
    var anticipating = false
    /// Frame rate: full while something is happening, a trickle at rest (blinks, breathing).
    var lively = true
    /// A still frame (pet card export): no timeline, no motion.
    var frozen = false
    /// Draw at this animation time instead of the clock (clip rendering).
    var time: Double? = nil
    /// The pointer is moving: animate the eyes even while resting.
    var tracking = false
    /// 0–1: the screen powering on (unboxing). nil: normal.
    var boot: Double? = nil
    var look: () -> CGFloat = { 0 }
    var lookY: () -> CGFloat = { 0 }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || frozen }

    private var restful: Bool { [.idle, .sleeping, .sleepy].contains(mood) && !anticipating }

    /// The collapsed notch shows the pet all day, so at rest it only redraws
    /// to blink (twice every 4.3 s) — continuous frames there cost ~5% CPU.
    private var schedule: GobSchedule {
        if time != nil || (reduceMotion && restful) { return GobSchedule(kind: .still) }
        if restful && !lively && !(tracking && mood != .sleeping) {
            return GobSchedule(kind: mood == .sleeping ? .still : .blinks)
        }
        // Collapsed-notch pet is tiny and can stay "working" for as long as an
        // agent runs: 15 fps there is indistinguishable and half the cost.
        if !lively { return GobSchedule(kind: .frames(1.0 / 15)) }
        return GobSchedule(kind: .frames(restful ? 1.0 / 10 : 1.0 / 30))
    }

    var body: some View {
        let character = self.character ?? PetModel.shared.character
        let colors = (skin ?? PetModel.shared.skin).map(GobColors.init)
        TimelineView(schedule) { context in
            Canvas { g, canvasSize in
                let now = context.date
                let pet = PetModel.shared
                GobPainter(mood: mood, hue: genome.species.hue, shiny: genome.shiny, stage: stage, hat: hat,
                           character: character, colors: colors,
                           t: time ?? (reduceMotion ? 0 : now.timeIntervalSinceReferenceDate),
                           look: look(), lookY: lookY(), anticipating: anticipating, extras: size >= 40,
                           keyAges: mood == .typing ? pet.keyTimes.map { now.timeIntervalSince($0) } : [],
                           heat: mood == .typing ? pet.typingHeat(at: now) : 0, boot: boot,
                           typed: mood == .typing ? pet.typedCount : 0)
                    .draw(in: &g, size: canvasSize)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Gob, \(mood.rawValue)")
    }
}

/// When GobView redraws: every frame, only at blink boundaries, or never.
struct GobSchedule: TimelineSchedule {
    enum Kind: Equatable {
        case frames(TimeInterval)
        case blinks
        case still
    }

    /// Must match GobPainter's blink cycle.
    static let blinkPeriod = 4.3
    static let blinkLength = 0.14

    var kind: Kind

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        switch kind {
        case .still:
            return AnySequence(CollectionOfOne(start))
        case .frames(let interval):
            let step = mode == .lowFrequency ? 1 : interval
            return AnySequence(sequence(first: start) { $0.addingTimeInterval(step) })
        case .blinks:
            // start, then each upcoming blink's close and reopen.
            let period = Self.blinkPeriod, length = Self.blinkLength
            let firstCycle = floor(start.timeIntervalSinceReferenceDate / period) + 1
            var k = -1
            return AnySequence(AnyIterator<Date> {
                defer { k += 1 }
                if k < 0 { return start }
                let t = (firstCycle + Double(k / 2)) * period + (k % 2 == 1 ? length : 0)
                return Date(timeIntervalSinceReferenceDate: t)
            })
        }
    }
}

/// A skin's colours, resolved once per draw.
struct GobColors {
    var top: Color
    var bottom: Color
    var face: Color?
    var cheeks: Color?
    var glow: Color?

    init(_ skin: PetSkin) {
        top = Color(skinHex: skin.bodyTop) ?? .gray
        bottom = Color(skinHex: skin.bodyBottom) ?? .gray
        face = Color(skinHex: skin.face)
        cheeks = Color(skinHex: skin.cheeks)
        glow = Color(skinHex: skin.glow)
    }
}

private struct GobPainter {
    let mood: Mood
    let hue: Double
    let shiny: Bool
    let stage: Int
    let hat: Hat
    let character: PetCharacter
    let colors: GobColors?
    let t: Double
    let look: CGFloat
    let lookY: CGFloat
    let anticipating: Bool
    let extras: Bool
    /// Seconds since each recent key press (typing mood only).
    let keyAges: [Double]
    /// 0–1 typing speed.
    let heat: Double
    /// 0–1 CRT power-on, or nil.
    let boot: Double?
    /// Key presses in this typing burst: one made-up character on the screen each.
    var typed: Int = 0

    /// How fresh the latest key press is: 1 right at the press, 0 after 0.15 s.
    private var keyPulse: CGFloat {
        guard let last = keyAges.last else { return 0 }
        return CGFloat(max(0, 1 - last / 0.15))
    }

    /// Phosphor: the face and the Matrix rain.
    private var ink: Color { colors?.glow ?? Palette.accent }
    private var cheekColor: Color { colors?.cheeks?.opacity(0.4) ?? Color(hex: 0xFF6FA5, alpha: 0.3) }

    /// Where the face goes, for hats that sit on it (sunglasses).
    private struct Face {
        var eyeY: CGFloat
        var eyeDX: CGFloat
        var eyeR: CGFloat
    }

    func draw(in c: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)

        // Motion: squash (+ wide/short, − tall/thin), bounce, sway, tilt. Cases are rigid, so it's subtle.
        var squash = sin(t * 2.2) * 0.012
        var dx: CGFloat = 0, dy: CGFloat = 0, tilt = 0.0
        switch mood {
        case .dancing:
            squash = sin(t * 8) * 0.035
            dx = CGFloat(sin(t * 4)) * s * 0.05
            tilt = sin(t * 4) * 0.12
        case .eating: squash = abs(sin(t * 14)) * 0.05
        case .burping: squash = -abs(sin(t * 10)) * 0.04
        case .celebrating:
            dy = -CGFloat(abs(sin(t * 7))) * s * 0.1
            squash = cos(t * 14) * 0.025
        case .dizzy: tilt = sin(t * 6) * 0.2
        case .love: squash = sin(t * 5) * 0.02
        case .alert: dx = CGFloat(sin(t * 40)) * s * 0.012
        case .working: dy = -CGFloat(abs(sin(t * 12))) * s * 0.01
        case .thinking: tilt = sin(t * 1.4) * 0.05
        case .typing:
            // A hop on every key press; faster typing, a bigger lean.
            dy = -keyPulse * s * 0.035
            squash = Double(keyPulse) * 0.03
            tilt = (heat - 0.5) * 0.06
        case .sweaty: dx = CGFloat(sin(t * 30)) * s * 0.006
        default: break
        }
        if anticipating { squash = -0.035 + sin(t * 9) * 0.01 }

        let base = CGPoint(x: s / 2 + dx, y: s * 0.95 + dy)
        c.translateBy(x: base.x, y: base.y)
        c.rotate(by: .radians(tilt))
        c.translateBy(x: -base.x, y: -base.y)

        let sq = CGFloat(squash)
        let (casing, screen): (CGRect, CGRect)
        switch character {
        case .classic: (casing, screen) = drawClassic(&c, s: s, sq: sq, base: base)
        case .retro: (casing, screen) = drawCompact(&c, s: s, sq: sq, base: base)
        case .candy: (casing, screen) = drawCandy(&c, s: s, sq: sq, base: base)
        }
        let face = drawScreen(&c, screen: screen, s: s)

        if hat != .none { drawHat(&c, body: casing, s: s, face: face) }
        if shiny { drawSparkles(&c, body: casing, s: s) }
        if mood == .sweaty { drawSweat(&c, body: casing, s: s) }
        if extras { drawExtras(&c, body: casing, s: s) }
    }

    // MARK: Cases

    /// Late-70s home computer: a sloped keyboard base with a boxy monitor on top.
    private func drawClassic(_ c: inout GraphicsContext, s: CGFloat, sq: CGFloat, base: CGPoint) -> (CGRect, CGRect) {
        let light = colors?.top ?? Color(hue: hue, saturation: 0.16, brightness: 0.93)
        let dark = colors?.bottom ?? Color(hue: hue, saturation: 0.24, brightness: 0.74)
        let shade = colors.map { $0.bottom.opacity(0.9) } ?? Color(hue: hue, saturation: 0.28, brightness: 0.5)

        // Keyboard base: a wedge, wider at the front.
        let kw = s * 0.92 * (1 + sq), kh = s * 0.22 * (1 - sq)
        let kb = CGRect(x: base.x - kw / 2, y: base.y - kh, width: kw, height: kh)
        var wedge = Path()
        wedge.move(to: CGPoint(x: kb.minX + kw * 0.07, y: kb.minY))
        wedge.addLine(to: CGPoint(x: kb.maxX - kw * 0.07, y: kb.minY))
        wedge.addLine(to: CGPoint(x: kb.maxX, y: kb.maxY - kh * 0.2))
        wedge.addQuadCurve(to: CGPoint(x: kb.maxX - kw * 0.04, y: kb.maxY), control: CGPoint(x: kb.maxX, y: kb.maxY))
        wedge.addLine(to: CGPoint(x: kb.minX + kw * 0.04, y: kb.maxY))
        wedge.addQuadCurve(to: CGPoint(x: kb.minX, y: kb.maxY - kh * 0.2), control: CGPoint(x: kb.minX, y: kb.maxY))
        wedge.closeSubpath()
        c.fill(wedge, with: .linearGradient(Gradient(colors: [light, dark]),
                                            startPoint: CGPoint(x: kb.midX, y: kb.minY), endPoint: CGPoint(x: kb.midX, y: kb.maxY)))
        // Keys: three rows of dark caps (two lines when tiny).
        let rows = s >= 40 ? 3 : 2
        for row in 0..<rows {
            let y = kb.minY + kh * (0.25 + CGFloat(row) * 0.22)
            let inset = kw * (0.13 - CGFloat(row) * 0.015)
            if s >= 40 {
                let count = 10, gap = kw * 0.012
                let keyW = (kw - 2 * inset - CGFloat(count - 1) * gap) / CGFloat(count)
                for k in 0..<count {
                    c.fill(Path(roundedRect: CGRect(x: kb.minX + inset + CGFloat(k) * (keyW + gap), y: y, width: keyW, height: kh * 0.14),
                                cornerRadius: keyW * 0.2), with: .color(shade.opacity(0.55)))
                }
            } else {
                c.fill(Path(CGRect(x: kb.minX + inset, y: y, width: kw - 2 * inset, height: max(1, kh * 0.12))), with: .color(shade.opacity(0.5)))
            }
        }

        // Monitor, sitting on the base.
        let mw = s * 0.66 * (1 + sq), mh = s * 0.56 * (1 - sq)
        let monitor = CGRect(x: base.x - mw / 2, y: kb.minY - mh + s * 0.015, width: mw, height: mh)
        let shell = Path(roundedRect: monitor, cornerRadius: mw * 0.07, style: .continuous)
        c.fill(shell, with: .linearGradient(Gradient(colors: [light, dark]),
                                            startPoint: CGPoint(x: monitor.midX, y: monitor.minY),
                                            endPoint: CGPoint(x: monitor.midX, y: monitor.maxY)))
        c.stroke(shell, with: .color(.white.opacity(0.3)), lineWidth: max(0.5, s * 0.008))
        let screen = CGRect(x: monitor.minX + mw * 0.1, y: monitor.minY + mh * 0.1, width: mw * 0.8, height: mh * 0.7)
        c.fill(Path(roundedRect: screen.insetBy(dx: -mw * 0.03, dy: -mw * 0.03), cornerRadius: mw * 0.06, style: .continuous),
               with: .color(shade.opacity(0.5)))
        // Power light and a disk slot on the base, which it eats through.
        let slot = CGRect(x: kb.maxX - kw * 0.3, y: kb.minY + kh * 0.06, width: kw * 0.18, height: max(1.2, kh * 0.08))
        if mood == .eating || anticipating { drawDisk(&c, slot: slot, size: kw * 0.12) }
        c.fill(Path(roundedRect: slot, cornerRadius: slot.height / 2), with: .color(.black.opacity(0.55)))
        c.fill(Path(ellipseIn: CGRect(x: monitor.maxX - mw * 0.12, y: monitor.maxY - mh * 0.12, width: mw * 0.04, height: mw * 0.04)),
               with: .color(busy ? ink : shade.opacity(0.6)))
        return (monitor, screen)
    }

    /// Mid-80s compact: tall case, CRT above vents and a floppy slot, little feet.
    private func drawCompact(_ c: inout GraphicsContext, s: CGFloat, sq: CGFloat, base: CGPoint) -> (CGRect, CGRect) {
        let w = s * 0.7 * (1 + sq), h = s * 0.8 * (1 - sq)
        let casing = CGRect(x: base.x - w / 2, y: base.y - s * 0.02 - h, width: w, height: h)
        let light = colors?.top ?? Color(hue: hue, saturation: 0.14, brightness: 0.96)
        let dark = colors?.bottom ?? Color(hue: hue, saturation: 0.2, brightness: 0.8)
        let shade = colors.map { $0.bottom.opacity(0.9) } ?? Color(hue: hue, saturation: 0.25, brightness: 0.55)

        for side in [-1.0, 1.0] {
            c.fill(Path(roundedRect: CGRect(x: casing.midX + CGFloat(side) * w * 0.3 - w * 0.1, y: casing.maxY - s * 0.01,
                                            width: w * 0.2, height: s * 0.04), cornerRadius: s * 0.02),
                   with: .color(shade))
        }
        let shell = Path(roundedRect: casing, cornerRadius: w * 0.13, style: .continuous)
        c.fill(shell, with: .linearGradient(Gradient(colors: [light, dark]),
                                            startPoint: CGPoint(x: casing.midX, y: casing.minY),
                                            endPoint: CGPoint(x: casing.midX, y: casing.maxY)))
        c.stroke(shell, with: .color(.white.opacity(0.35)), lineWidth: max(0.5, s * 0.008))

        let screen = CGRect(x: casing.minX + w * 0.13, y: casing.minY + h * 0.09, width: w * 0.74, height: h * 0.52)
        c.fill(Path(roundedRect: screen.insetBy(dx: -w * 0.035, dy: -w * 0.035), cornerRadius: w * 0.1, style: .continuous),
               with: .color(shade.opacity(0.55)))

        let slot = CGRect(x: casing.midX - w * 0.02, y: casing.minY + h * 0.76, width: w * 0.34, height: max(1.5, h * 0.035))
        if mood == .eating || anticipating { drawDisk(&c, slot: slot, size: w * 0.22) }
        c.fill(Path(roundedRect: slot, cornerRadius: slot.height / 2), with: .color(.black.opacity(0.6)))
        let led = CGRect(x: slot.maxX - w * 0.07, y: slot.maxY + h * 0.035, width: w * 0.05, height: max(1, h * 0.022))
        c.fill(Path(roundedRect: led, cornerRadius: led.height / 2), with: .color(busy && sin(t * 20) > -0.3 ? ink : shade.opacity(0.6)))
        for i in 0..<3 {
            c.fill(Path(roundedRect: CGRect(x: casing.minX + w * 0.13 + CGFloat(i) * w * 0.05, y: slot.minY - h * 0.01,
                                            width: max(1, w * 0.018), height: h * 0.08), cornerRadius: 1),
                   with: .color(shade.opacity(0.45)))
        }
        return (casing, screen)
    }

    /// Late-90s bubble computer: one rounded candy-coloured shell with a
    /// ribbed, glossy look, a CD slot and speaker dots, on a small foot.
    private func drawCandy(_ c: inout GraphicsContext, s: CGFloat, sq: CGFloat, base: CGPoint) -> (CGRect, CGRect) {
        let w = s * 0.8 * (1 + sq), h = s * 0.76 * (1 - sq)
        let body = CGRect(x: base.x - w / 2, y: base.y - s * 0.05 - h, width: w, height: h)
        let light = colors?.top ?? Color(hue: hue, saturation: 0.5, brightness: 1)
        let dark = colors?.bottom ?? Color(hue: hue, saturation: 0.88, brightness: 0.74)

        // Foot.
        c.fill(Path(ellipseIn: CGRect(x: base.x - w * 0.24, y: base.y - s * 0.07, width: w * 0.48, height: s * 0.07)),
               with: .color(dark.opacity(0.85)))
        // Shell: rounder at the bottom, like a gumdrop on its side.
        var shell = Path()
        let r = w * 0.2
        shell.move(to: CGPoint(x: body.minX + r, y: body.minY))
        shell.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        shell.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + r), control: CGPoint(x: body.maxX, y: body.minY))
        shell.addLine(to: CGPoint(x: body.maxX - w * 0.02, y: body.maxY - h * 0.3))
        shell.addQuadCurve(to: CGPoint(x: body.midX, y: body.maxY), control: CGPoint(x: body.maxX - w * 0.06, y: body.maxY))
        shell.addQuadCurve(to: CGPoint(x: body.minX + w * 0.02, y: body.maxY - h * 0.3), control: CGPoint(x: body.minX + w * 0.06, y: body.maxY))
        shell.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        shell.addQuadCurve(to: CGPoint(x: body.minX + r, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        shell.closeSubpath()
        c.fill(shell, with: .linearGradient(Gradient(colors: [light, dark]),
                                            startPoint: CGPoint(x: body.midX, y: body.minY), endPoint: CGPoint(x: body.midX, y: body.maxY)))
        // Ribs in the lower shell, and a gloss sweep.
        var ribs = c
        ribs.clip(to: shell)
        if s >= 40 {
            for i in 0..<9 {
                let x = body.minX + w * (0.08 + CGFloat(i) * 0.105)
                ribs.fill(Path(CGRect(x: x, y: body.minY + h * 0.72, width: w * 0.035, height: h * 0.3)), with: .color(.white.opacity(0.13)))
            }
        }
        ribs.fill(Path(ellipseIn: CGRect(x: body.minX - w * 0.1, y: body.minY - h * 0.25, width: w * 0.9, height: h * 0.55)),
                  with: .color(.white.opacity(0.16)))
        c.stroke(shell, with: .color(.white.opacity(0.45)), lineWidth: max(0.5, s * 0.009))

        let screen = CGRect(x: body.minX + w * 0.15, y: body.minY + h * 0.11, width: w * 0.7, height: h * 0.5)
        c.stroke(Path(roundedRect: screen.insetBy(dx: -w * 0.025, dy: -w * 0.025), cornerRadius: w * 0.11, style: .continuous),
                 with: .color(.white.opacity(0.55)), lineWidth: max(1, s * 0.02))

        let slot = CGRect(x: body.midX - w * 0.16, y: body.minY + h * 0.72, width: w * 0.32, height: max(1.5, h * 0.03))
        if mood == .eating || anticipating {
            // A disc slides in instead of a floppy.
            let phase = anticipating ? 0 : CGFloat((t * 1.4).truncatingRemainder(dividingBy: 1))
            let d = w * 0.24
            let disc = CGRect(x: slot.midX - d / 2, y: slot.midY - d * (1 - phase), width: d, height: d * (1 - phase))
            c.fill(Path(ellipseIn: disc), with: .conicGradient(Gradient(colors: [.white, Color(hex: 0xB9E4FF), Color(hex: 0xFFC9E6), .white]),
                                                               center: CGPoint(x: disc.midX, y: disc.midY)))
            c.fill(Path(ellipseIn: CGRect(x: disc.midX - d * 0.08, y: disc.midY - disc.height * 0.08, width: d * 0.16, height: disc.height * 0.16)),
                   with: .color(dark))
        }
        c.fill(Path(roundedRect: slot, cornerRadius: slot.height / 2), with: .color(.black.opacity(0.45)))
        if s >= 40 {
            for side in [-1.0, 1.0] {
                for row in 0..<2 {
                    for col in 0..<3 {
                        let x = body.midX + CGFloat(side) * w * (0.27 + CGFloat(col) * 0.035)
                        let y = slot.midY - h * 0.03 + CGFloat(row) * h * 0.05
                        c.fill(Path(ellipseIn: CGRect(x: x - s * 0.006, y: y - s * 0.006, width: s * 0.012, height: s * 0.012)),
                               with: .color(.black.opacity(0.3)))
                    }
                }
            }
        }
        return (body, screen)
    }

    private var busy: Bool { [.eating, .working, .burping, .thinking].contains(mood) }

    /// A floppy on its way into a slot.
    private func drawDisk(_ c: inout GraphicsContext, slot: CGRect, size: CGFloat) {
        let phase = anticipating ? 0 : CGFloat((t * 1.4).truncatingRemainder(dividingBy: 1))
        let disk = CGRect(x: slot.midX - size / 2, y: slot.midY - size * (1 - phase), width: size, height: size * (1 - phase))
        c.fill(Path(roundedRect: disk, cornerRadius: size * 0.06), with: .color(Color(hex: 0x3E6BE0)))
        c.fill(Path(CGRect(x: disk.minX + size * 0.25, y: disk.minY, width: size * 0.5, height: min(disk.height, size * 0.3))),
               with: .color(Color(hex: 0xC9D2E0)))
    }

    // MARK: Screen

    /// CRT glass, then the face (or Matrix rain while an agent codes), then scanlines.
    private func drawScreen(_ c: inout GraphicsContext, screen: CGRect, s: CGFloat) -> Face {
        let glass = Path(roundedRect: screen, cornerRadius: screen.width * 0.1, style: .continuous)
        c.fill(glass, with: .radialGradient(Gradient(colors: [Color(hex: 0x1F3A28), Color(hex: 0x0A120D)]),
                                            center: CGPoint(x: screen.midX, y: screen.midY), startRadius: 0, endRadius: screen.width * 0.7))
        let face = Face(eyeY: screen.minY + screen.height * 0.4, eyeDX: screen.width * 0.2, eyeR: screen.width * 0.075)
        let line = max(1, s * 0.03)
        // Powering on: dark → a line → a flash with "Hi!" → the face fades in.
        let fade = boot.map { max(0, min(1, ($0 - 0.72) / 0.28)) } ?? 1

        if let boot, boot < 0.72 {
            drawBoot(&c, screen: screen, glass: glass, s: s, p: CGFloat(boot))
        } else if mood == .working {
            var rain = c
            rain.clip(to: glass)
            drawMatrix(&rain, screen: screen, s: s)
            // Eyes squint through the code.
            drawEyes(&c, center: CGPoint(x: screen.midX, y: face.eyeY), face: face, line: line, color: .white.opacity(0.92))
        } else if mood == .typing {
            // Typing along with the user: eyes on the text, characters filling the screen.
            var glow = c
            if s >= 40 { glow.addFilter(.shadow(color: ink.opacity(0.8), radius: s * 0.02)) }
            drawEyes(&glow, center: CGPoint(x: screen.midX, y: screen.minY + screen.height * 0.3),
                     face: Face(eyeY: screen.minY + screen.height * 0.3, eyeDX: face.eyeDX, eyeR: face.eyeR * 0.85),
                     line: line, color: ink)
            drawTyped(&glow, screen: screen, s: s)
        } else if mood == .listening {
            var glow = c
            if s >= 40 { glow.addFilter(.shadow(color: ink.opacity(0.8), radius: s * 0.02)) }
            drawEyes(&glow, center: CGPoint(x: screen.midX, y: face.eyeY), face: face, line: line, color: ink)
            drawWaveform(&glow, screen: screen, s: s)
        } else {
            var glow = c
            glow.opacity = fade
            if s >= 40 { glow.addFilter(.shadow(color: ink.opacity(0.8), radius: s * 0.02)) }
            drawEyes(&glow, center: CGPoint(x: screen.midX, y: face.eyeY), face: face, line: line, color: ink)
            drawMouth(&glow, center: CGPoint(x: screen.midX, y: screen.minY + screen.height * 0.73),
                      w: screen.width, h: screen.height, s: s * 0.75, line: line)
            for side in [-1.0, 1.0] {
                c.fill(Path(roundedRect: CGRect(x: screen.midX + CGFloat(side) * face.eyeDX * 1.6 - face.eyeR, y: face.eyeY + face.eyeR * 1.3,
                                                width: face.eyeR * 2, height: face.eyeR * 0.8), cornerRadius: face.eyeR * 0.3),
                       with: .color(cheekColor))
            }
            if mood == .thinking {
                // Three dots taking turns: readable even at notch size.
                for i in 0..<3 {
                    let on = Int(t * 3) % 3 == i
                    let d = max(1.2, screen.width * 0.05)
                    c.fill(Path(ellipseIn: CGRect(x: screen.maxX - screen.width * 0.3 + CGFloat(i) * d * 1.6, y: screen.maxY - screen.height * 0.16,
                                                  width: d, height: d)),
                           with: .color(ink.opacity(on ? 1 : 0.3)))
                }
            }
        }
        if s >= 40 {
            var y = screen.minY + s * 0.01
            while y < screen.maxY - s * 0.005 {
                c.fill(Path(CGRect(x: screen.minX + screen.width * 0.03, y: y, width: screen.width * 0.94, height: max(0.5, s * 0.004))),
                       with: .color(.black.opacity(0.22)))
                y += s * 0.018
            }
        }
        c.fill(Path(ellipseIn: CGRect(x: screen.minX + screen.width * 0.08, y: screen.minY + screen.height * 0.06,
                                      width: screen.width * 0.3, height: screen.height * 0.14)),
               with: .color(.white.opacity(0.07)))
        return face
    }

    /// An old CRT switching on.
    private func drawBoot(_ c: inout GraphicsContext, screen: CGRect, glass: Path, s: CGFloat, p: CGFloat) {
        guard p >= 0.2 else { return } // still dark
        if p < 0.42 {
            // A dot stretches into a line, then the line opens into a picture.
            let k = (p - 0.2) / 0.22
            let w = screen.width * min(1, k * 2)
            let h = max(1, screen.height * max(0, k * 2 - 1) * 0.9 + s * 0.008)
            var line = c
            line.addFilter(.shadow(color: .white, radius: s * 0.03))
            line.fill(Path(roundedRect: CGRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h), cornerRadius: h / 2),
                      with: .color(.white.opacity(0.95)))
        } else {
            // A white flash settling into phosphor green, and a greeting.
            let k = Double((p - 0.42) / 0.3)
            c.fill(glass, with: .color(.white.opacity(max(0, 0.85 - k * 1.2))))
            var text = c
            text.opacity = min(1, k * 2)
            if s >= 40 { text.addFilter(.shadow(color: ink, radius: s * 0.03)) }
            text.draw(Text("Hi!").font(.system(size: screen.height * 0.36, weight: .heavy, design: .monospaced)).foregroundColor(ink),
                      at: CGPoint(x: screen.midX, y: screen.midY))
        }
    }

    /// One made-up character per key press, a few lines that scroll, and a
    /// blinking cursor. The real keys are never known: characters come from
    /// the press count. Tiny sizes draw blocks instead of letters.
    private func drawTyped(_ c: inout GraphicsContext, screen: CGRect, s: CGFloat) {
        let big = s >= 40
        let cols = big ? 7 : 5
        let rows = big ? 3 : 2
        let area = CGRect(x: screen.minX + screen.width * 0.12, y: screen.minY + screen.height * 0.5,
                          width: screen.width * 0.76, height: screen.height * 0.4)
        let cellW = area.width / CGFloat(cols)
        let cellH = area.height / CGFloat(rows)
        let glyphs = Array("abcdefghijklmnopqrstuvwxyz{}()=;<>/+*")
        let total = max(0, typed)
        let cursorRow = total / cols
        let firstRow = max(0, cursorRow - rows + 1)
        for row in firstRow...cursorRow {
            let y = area.minY + (CGFloat(row - firstRow) + 0.5) * cellH
            for col in 0..<(row == cursorRow ? total % cols : cols) {
                let index = row * cols + col
                var rng = SplitMix64(seed: UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15)
                let r = rng.next()
                if r % 7 == 0 { continue } // a space now and then
                let x = area.minX + (CGFloat(col) + 0.5) * cellW
                let color = index == total - 1 && keyPulse > 0 ? Color.white : ink
                if big {
                    c.draw(Text(String(glyphs[Int(r % UInt64(glyphs.count))]))
                            .font(.system(size: cellH * 0.95, weight: .heavy, design: .monospaced)).foregroundColor(color),
                           at: CGPoint(x: x, y: y))
                } else {
                    c.fill(Path(CGRect(x: x - cellW * 0.35, y: y - cellH * 0.22, width: cellW * 0.7, height: cellH * 0.44)),
                           with: .color(color))
                }
            }
        }
        // The cursor: solid while keys land, blinking in the pauses.
        if keyPulse > 0 || Int(t * 2.5) % 2 == 0 {
            let x = area.minX + (CGFloat(total % cols) + 0.5) * cellW
            let y = area.minY + (CGFloat(cursorRow - firstRow) + 0.5) * cellH
            c.fill(Path(CGRect(x: x - cellW * 0.3, y: y - cellH * 0.36, width: cellW * 0.6, height: cellH * 0.72)), with: .color(ink))
        }
    }

    /// Where the mouth would be: bars that follow the microphone level.
    private func drawWaveform(_ c: inout GraphicsContext, screen: CGRect, s: CGFloat) {
        let bars = s >= 40 ? 9 : 5
        let level = CGFloat(max(0.08, min(1, MicLevel.value)))
        let span = screen.width * 0.56
        let step = span / CGFloat(bars)
        let midY = screen.minY + screen.height * 0.74
        let maxH = screen.height * 0.3
        for i in 0..<bars {
            // Taller in the middle, each bar wobbling at its own rate.
            let centre = 1 - abs(CGFloat(i) - CGFloat(bars - 1) / 2) / CGFloat(bars)
            let wobble = 0.55 + 0.45 * CGFloat(abs(sin(t * (6 + Double(i) * 1.7) + Double(i))))
            let h = max(step * 0.5, maxH * level * centre * wobble)
            let x = screen.midX - span / 2 + (CGFloat(i) + 0.5) * step
            c.fill(Path(roundedRect: CGRect(x: x - step * 0.22, y: midY - h / 2, width: step * 0.44, height: h), cornerRadius: step * 0.22),
                   with: .color(ink))
        }
    }

    /// Columns of falling glyphs, bright at the head and fading behind.
    private func drawMatrix(_ c: inout GraphicsContext, screen: CGRect, s: CGFloat) {
        let cell = max(2.4, s * 0.045)
        let cols = max(4, Int(screen.width / cell))
        let rows = Int(screen.height / cell) + 1
        let colW = screen.width / CGFloat(cols)
        let glyphs = Array("01アイウエオカキクケコサシスセソタチツテトﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘｱﾎﾃﾏｹﾒｴｶｷﾑﾕﾗｾﾈｽﾀﾇﾍ")
        let tick = UInt64(max(0, t * 8))
        for col in 0..<cols {
            var rng = SplitMix64(seed: UInt64(col + 1) &* 0x9E37_79B9_7F4A_7C15)
            let speed = 4 + Double(rng.next() % 6)
            let offset = Double(rng.next() % 97)
            let trail = 4 + Int(rng.next() % 5)
            let head = Int((t * speed + offset).truncatingRemainder(dividingBy: Double(rows + trail)))
            let x = screen.minX + (CGFloat(col) + 0.5) * colW
            for k in 0..<trail {
                let row = head - k
                guard row >= 0, row < rows else { continue }
                let y = screen.minY + (CGFloat(row) + 0.5) * cell
                let color = k == 0 ? Color.white.opacity(0.95) : ink.opacity(0.85 * (1 - Double(k) / Double(trail)))
                if s >= 40 {
                    let index = Int((UInt64(col * 131 + row * 17) &+ tick) % UInt64(glyphs.count))
                    c.draw(Text(String(glyphs[index])).font(.system(size: cell * 0.95, weight: .bold, design: .monospaced))
                            .foregroundColor(color), at: CGPoint(x: x, y: y))
                } else {
                    c.fill(Path(CGRect(x: x - cell * 0.18, y: y - cell * 0.32, width: cell * 0.36, height: cell * 0.64)), with: .color(color))
                }
            }
        }
    }

    private func drawEyes(_ c: inout GraphicsContext, center: CGPoint, face: Face, line: CGFloat, color: Color) {
        let r = face.eyeR, dx = face.eyeDX
        let blink = t.truncatingRemainder(dividingBy: GobSchedule.blinkPeriod) < GobSchedule.blinkLength - 0.01
        let stroke = StrokeStyle(lineWidth: line, lineCap: .round)
        for side in [-1.0, 1.0] {
            let e = CGPoint(x: center.x + CGFloat(side) * dx, y: center.y)
            switch mood {
            case .sleeping:
                var p = Path()
                p.move(to: CGPoint(x: e.x - r, y: e.y))
                p.addQuadCurve(to: CGPoint(x: e.x + r, y: e.y), control: CGPoint(x: e.x, y: e.y + r * 0.9))
                c.stroke(p, with: .color(color), style: stroke)
            case .happy, .celebrating, .dancing:
                var p = Path()
                p.move(to: CGPoint(x: e.x - r, y: e.y + r * 0.3))
                p.addQuadCurve(to: CGPoint(x: e.x + r, y: e.y + r * 0.3), control: CGPoint(x: e.x, y: e.y - r * 1.2))
                c.stroke(p, with: .color(color), style: stroke)
            case .love:
                c.fill(heart(center: e, size: r * 2.3), with: .color(Color(hex: 0xFF6FA5)))
            case .dizzy:
                var p = Path()
                p.move(to: CGPoint(x: e.x - r * 0.8, y: e.y - r * 0.8))
                p.addLine(to: CGPoint(x: e.x + r * 0.8, y: e.y + r * 0.8))
                p.move(to: CGPoint(x: e.x + r * 0.8, y: e.y - r * 0.8))
                p.addLine(to: CGPoint(x: e.x - r * 0.8, y: e.y + r * 0.8))
                c.stroke(p, with: .color(color), style: stroke)
            default:
                if blink && mood != .thinking {
                    var p = Path()
                    p.move(to: CGPoint(x: e.x - r, y: e.y))
                    p.addLine(to: CGPoint(x: e.x + r, y: e.y))
                    c.stroke(p, with: .color(color), style: stroke)
                    continue
                }
                let big: CGFloat = anticipating || mood == .alert || mood == .curious || mood == .sweaty ? 1.25 : 1
                let lid: CGFloat = mood == .sleepy ? 0.55 : (mood == .working ? 0.5 : (mood == .thinking ? 0.85 : 1))
                let w = r * 1.5 * big, h = r * 2 * big * lid
                var px = e.x + max(-1, min(1, look)) * r * 0.45
                var py = e.y + max(-1, min(1, lookY)) * r * 0.35
                switch mood {
                case .typing:
                    // Watching the keyboard.
                    px = e.x + CGFloat(sin(t * 7)) * r * 0.2
                    py = e.y + r * 0.35
                case .working:
                    // Reading the code: flicking side to side, looking down.
                    px = e.x + CGFloat(sin(t * 5)) * r * 0.3
                    py = e.y + r * 0.35
                case .thinking:
                    // Looking up and away, the way people do when they think.
                    px = e.x + r * 0.45
                    py = e.y - r * 0.4
                default:
                    break
                }
                c.fill(Path(roundedRect: CGRect(x: px - w / 2, y: py - h / 2, width: w, height: h), cornerRadius: w * 0.25), with: .color(color))
                if mood == .thinking && side > 0 {
                    // One raised eyebrow.
                    var brow = Path()
                    brow.move(to: CGPoint(x: e.x - r * 0.9, y: e.y - r * 1.55))
                    brow.addLine(to: CGPoint(x: e.x + r * 0.9, y: e.y - r * 2.05))
                    c.stroke(brow, with: .color(color), style: stroke)
                }
            }
        }
    }

    private func heart(center p: CGPoint, size: CGFloat) -> Path {
        var h = Path()
        let s = size / 2
        h.move(to: CGPoint(x: p.x, y: p.y + s * 0.8))
        h.addCurve(to: CGPoint(x: p.x - s, y: p.y - s * 0.2), control1: CGPoint(x: p.x - s * 0.4, y: p.y + s * 0.5), control2: CGPoint(x: p.x - s, y: p.y + s * 0.2))
        h.addArc(center: CGPoint(x: p.x - s * 0.5, y: p.y - s * 0.25), radius: s * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        h.addArc(center: CGPoint(x: p.x + s * 0.5, y: p.y - s * 0.25), radius: s * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        h.addCurve(to: CGPoint(x: p.x, y: p.y + s * 0.8), control1: CGPoint(x: p.x + s, y: p.y + s * 0.2), control2: CGPoint(x: p.x + s * 0.4, y: p.y + s * 0.5))
        h.closeSubpath()
        return h
    }

    private func drawMouth(_ c: inout GraphicsContext, center m: CGPoint, w: CGFloat, h: CGFloat, s: CGFloat, line: CGFloat) {
        let stroke = StrokeStyle(lineWidth: line, lineCap: .round)
        switch mood {
        case _ where anticipating || mood == .eating:
            let mw = w * (anticipating ? 0.32 : 0.28)
            let mh = anticipating ? h * 0.24 : h * CGFloat(0.06 + abs(sin(t * 14)) * 0.16)
            c.fill(Path(ellipseIn: CGRect(x: m.x - mw / 2, y: m.y - mh / 2, width: mw, height: mh)), with: .color(ink))
        case .burping, .alert, .dizzy:
            let r = s * (mood == .burping ? 0.06 : 0.045)
            c.fill(Path(ellipseIn: CGRect(x: m.x - r, y: m.y - r, width: r * 2, height: r * 2)), with: .color(ink))
        case .sweaty:
            var p = Path()
            p.move(to: CGPoint(x: m.x - w * 0.1, y: m.y))
            for i in 1...4 {
                p.addLine(to: CGPoint(x: m.x - w * 0.1 + w * 0.05 * CGFloat(i), y: m.y + (i.isMultiple(of: 2) ? 0 : h * 0.04)))
            }
            c.stroke(p, with: .color(ink), style: stroke)
        case .thinking:
            // A sideways "hmm".
            var p = Path()
            p.move(to: CGPoint(x: m.x - w * 0.05, y: m.y + h * 0.02))
            p.addLine(to: CGPoint(x: m.x + w * 0.07, y: m.y - h * 0.03))
            c.stroke(p, with: .color(ink), style: stroke)
        case .sleepy, .sleeping, .working:
            var p = Path()
            p.move(to: CGPoint(x: m.x - w * 0.05, y: m.y))
            p.addLine(to: CGPoint(x: m.x + w * 0.05, y: m.y))
            c.stroke(p, with: .color(ink), style: stroke)
        default:
            let wide: CGFloat = [.happy, .love, .celebrating, .dancing].contains(mood) ? 0.13 : 0.08
            var p = Path()
            p.move(to: CGPoint(x: m.x - w * wide, y: m.y - h * 0.02))
            p.addQuadCurve(to: CGPoint(x: m.x + w * wide, y: m.y - h * 0.02),
                           control: CGPoint(x: m.x, y: m.y + h * (wide > 0.1 ? 0.14 : 0.08)))
            c.stroke(p, with: .color(ink), style: stroke)
        }
    }

    // MARK: Hats

    private func drawHat(_ c: inout GraphicsContext, body: CGRect, s: CGFloat, face: Face) {
        let top = body.minY
        let cx = body.midX
        let w = body.width
        switch hat {
        case .none:
            break
        case .party:
            let base = CGPoint(x: cx - w * 0.18, y: top + s * 0.03)
            var cone = Path()
            cone.move(to: CGPoint(x: base.x - s * 0.11, y: base.y))
            cone.addLine(to: CGPoint(x: base.x + s * 0.03, y: base.y - s * 0.3))
            cone.addLine(to: CGPoint(x: base.x + s * 0.13, y: base.y + s * 0.01))
            cone.closeSubpath()
            c.fill(cone, with: .linearGradient(Gradient(colors: [Color(hex: 0x5B9CF6), Color(hex: 0x9D7CF6)]),
                                               startPoint: base, endPoint: CGPoint(x: base.x, y: base.y - s * 0.3)))
            for i in 1...2 {
                let y = base.y - s * 0.1 * CGFloat(i)
                c.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.02 + CGFloat(i) * s * 0.01, y: y - s * 0.015, width: s * 0.04, height: s * 0.03)),
                       with: .color(Palette.gold))
            }
            c.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.005, y: base.y - s * 0.34, width: s * 0.07, height: s * 0.07)),
                   with: .color(Color(hex: 0xFF6FA5)))
        case .bow:
            let p = CGPoint(x: cx - w * 0.3, y: top + s * 0.04)
            let r = s * 0.075
            for side in [-1.0, 1.0] {
                var wing = Path()
                wing.move(to: p)
                wing.addQuadCurve(to: CGPoint(x: p.x + CGFloat(side) * r * 1.6, y: p.y - r),
                                  control: CGPoint(x: p.x + CGFloat(side) * r * 0.6, y: p.y - r * 1.4))
                wing.addQuadCurve(to: p, control: CGPoint(x: p.x + CGFloat(side) * r * 1.8, y: p.y + r * 0.8))
                c.fill(wing, with: .color(Color(hex: 0xFF5C8A)))
            }
            c.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.4, y: p.y - r * 0.5, width: r * 0.8, height: r * 0.8)),
                   with: .color(Color(hex: 0xE23D6D)))
        case .beanie, .santa:
            let red = hat == .santa
            let brim = CGRect(x: body.minX + w * 0.1, y: top - s * 0.02, width: w * 0.8, height: s * 0.07)
            var dome = Path()
            dome.move(to: CGPoint(x: brim.minX + s * 0.01, y: brim.minY + 2))
            if red {
                dome.addQuadCurve(to: CGPoint(x: brim.maxX + s * 0.12, y: brim.minY - s * 0.1),
                                  control: CGPoint(x: cx, y: top - s * 0.34))
                dome.addLine(to: CGPoint(x: brim.maxX - s * 0.01, y: brim.minY + 2))
            } else {
                dome.addQuadCurve(to: CGPoint(x: brim.maxX - s * 0.01, y: brim.minY + 2),
                                  control: CGPoint(x: cx, y: top - s * 0.28))
            }
            dome.closeSubpath()
            c.fill(dome, with: .color(red ? Color(hex: 0xE0343B) : Color(hex: 0x3E6BE0)))
            c.fill(Path(roundedRect: brim, cornerRadius: brim.height / 2), with: .color(red ? .white : Color(hex: 0x2B4FB5)))
            let pom = red ? CGPoint(x: brim.maxX + s * 0.12, y: brim.minY - s * 0.1) : CGPoint(x: cx, y: top - s * 0.15)
            c.fill(Path(ellipseIn: CGRect(x: pom.x - s * 0.045, y: pom.y - s * 0.045, width: s * 0.09, height: s * 0.09)),
                   with: .color(.white))
        case .headphones:
            var band = Path()
            band.move(to: CGPoint(x: body.minX + w * 0.02, y: top + body.height * 0.35))
            band.addQuadCurve(to: CGPoint(x: body.maxX - w * 0.02, y: top + body.height * 0.35),
                              control: CGPoint(x: cx, y: top - s * 0.24))
            c.stroke(band, with: .color(Color(hex: 0x2A2D33)), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
            for side in [-1.0, 1.0] {
                let x = side < 0 ? body.minX - s * 0.05 : body.maxX - s * 0.05
                c.fill(Path(roundedRect: CGRect(x: x, y: top + body.height * 0.25, width: s * 0.1, height: s * 0.17), cornerRadius: s * 0.04),
                       with: .color(Palette.accent))
            }
        case .sunglasses:
            let r = face.eyeR
            for side in [-1.0, 1.0] {
                let e = CGPoint(x: cx + CGFloat(side) * face.eyeDX, y: face.eyeY)
                c.fill(Path(roundedRect: CGRect(x: e.x - r * 1.35, y: e.y - r * 0.95, width: r * 2.7, height: r * 1.9), cornerRadius: r * 0.7),
                       with: .color(Color(hex: 0x111114)))
                c.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.9, y: e.y - r * 0.6, width: r * 0.7, height: r * 0.35)),
                       with: .color(.white.opacity(0.5)))
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: cx - face.eyeDX + r * 1.3, y: face.eyeY - r * 0.3))
            bridge.addLine(to: CGPoint(x: cx + face.eyeDX - r * 1.3, y: face.eyeY - r * 0.3))
            c.stroke(bridge, with: .color(Color(hex: 0x111114)), lineWidth: max(1, s * 0.02))
        case .halo:
            let bob = CGFloat(sin(t * 2)) * s * 0.01
            c.stroke(Path(ellipseIn: CGRect(x: cx - w * 0.3, y: top - s * 0.14 + bob, width: w * 0.6, height: s * 0.08)),
                     with: .color(Palette.gold), lineWidth: max(1.5, s * 0.03))
        case .crown:
            let cw = s * 0.24, ch = s * 0.13
            let x = cx - cw / 2, y = top + s * 0.01
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x, y: y - ch))
            p.addLine(to: CGPoint(x: x + cw * 0.25, y: y - ch * 0.5))
            p.addLine(to: CGPoint(x: x + cw * 0.5, y: y - ch * 1.1))
            p.addLine(to: CGPoint(x: x + cw * 0.75, y: y - ch * 0.5))
            p.addLine(to: CGPoint(x: x + cw, y: y - ch))
            p.addLine(to: CGPoint(x: x + cw, y: y))
            p.closeSubpath()
            c.fill(p, with: .color(Palette.gold))
            c.fill(Path(ellipseIn: CGRect(x: cx - s * 0.02, y: y - ch * 0.45, width: s * 0.04, height: s * 0.04)),
                   with: .color(Color(hex: 0xE23D6D)))
        case .flower:
            let p = CGPoint(x: cx + w * 0.34, y: top + s * 0.03)
            let r = s * 0.04
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi + t * 0.5
                c.fill(Path(ellipseIn: CGRect(x: p.x + CGFloat(cos(a)) * r - r, y: p.y + CGFloat(sin(a)) * r - r, width: r * 2, height: r * 2)),
                       with: .color(Color(hex: 0xFFB3D1)))
            }
            c.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.7, y: p.y - r * 0.7, width: r * 1.4, height: r * 1.4)), with: .color(Palette.gold))
        case .pumpkin:
            let pw = s * 0.3, ph = s * 0.2
            let rect = CGRect(x: cx - pw / 2, y: top - ph * 0.7, width: pw, height: ph)
            for i in 0..<3 {
                let x = rect.minX + CGFloat(i) * pw * 0.25
                c.fill(Path(ellipseIn: CGRect(x: x, y: rect.minY, width: pw * 0.5, height: ph)),
                       with: .color(i == 1 ? Color(hex: 0xFF8A1F) : Color(hex: 0xE8700C)))
            }
            c.fill(Path(roundedRect: CGRect(x: cx - s * 0.015, y: rect.minY - s * 0.06, width: s * 0.03, height: s * 0.07), cornerRadius: s * 0.01),
                   with: .color(Color(hex: 0x4E7A2A)))
        case .diya:
            let bowl = CGRect(x: cx - s * 0.12, y: top - s * 0.07, width: s * 0.24, height: s * 0.09)
            var cup = Path()
            cup.move(to: CGPoint(x: bowl.minX, y: bowl.minY))
            cup.addQuadCurve(to: CGPoint(x: bowl.maxX, y: bowl.minY), control: CGPoint(x: bowl.midX, y: bowl.maxY + s * 0.06))
            cup.closeSubpath()
            c.fill(cup, with: .color(Color(hex: 0xC8652B)))
            let flicker = CGFloat(sin(t * 12)) * s * 0.008
            var flame = Path()
            flame.move(to: CGPoint(x: bowl.midX, y: bowl.minY))
            flame.addQuadCurve(to: CGPoint(x: bowl.midX + flicker, y: bowl.minY - s * 0.13),
                               control: CGPoint(x: bowl.midX + s * 0.06, y: bowl.minY - s * 0.04))
            flame.addQuadCurve(to: CGPoint(x: bowl.midX, y: bowl.minY),
                               control: CGPoint(x: bowl.midX - s * 0.06, y: bowl.minY - s * 0.04))
            c.fill(flame, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE27A), Color(hex: 0xFF8A1F)]),
                                                startPoint: CGPoint(x: bowl.midX, y: bowl.minY - s * 0.13),
                                                endPoint: CGPoint(x: bowl.midX, y: bowl.minY)))
        }
    }

    private func drawSparkles(_ c: inout GraphicsContext, body: CGRect, s: CGFloat) {
        for i in 0..<3 {
            let phase = (t * 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let a = Double(i) * 2.1 + 0.6
            let p = CGPoint(x: body.midX + CGFloat(cos(a)) * body.width * 0.6,
                            y: body.midY + CGFloat(sin(a)) * body.height * 0.62)
            let r = s * 0.06 * CGFloat(sin(phase * .pi))
            var star = Path()
            star.move(to: CGPoint(x: p.x, y: p.y - r))
            star.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: p)
            c.fill(star, with: .color(.white.opacity(0.9)))
        }
    }

    private func drawSweat(_ c: inout GraphicsContext, body: CGRect, s: CGFloat) {
        let phase = CGFloat((t * 0.8).truncatingRemainder(dividingBy: 1))
        let p = CGPoint(x: body.maxX - body.width * 0.05, y: body.minY + body.height * (0.12 + 0.4 * phase))
        let r = s * 0.05
        var drop = Path()
        drop.move(to: CGPoint(x: p.x, y: p.y - r * 1.6))
        drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: CGPoint(x: p.x + r * 1.6, y: p.y + r))
        drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r * 1.6), control: CGPoint(x: p.x - r * 1.6, y: p.y + r))
        c.fill(drop, with: .color(Color(hex: 0x7CC8FF).opacity(Double(1 - phase * 0.6))))
    }

    /// Floating extras: z's, hearts, notes, confetti, a thought bubble. Only at sizes where they read.
    private func drawExtras(_ c: inout GraphicsContext, body: CGRect, s: CGFloat) {
        let glyph: String?
        let color: Color
        switch mood {
        case .sleeping: glyph = "z"; color = .white
        case .love: glyph = "♥"; color = Color(hex: 0xFF6FA5)
        case .dancing: glyph = "♪"; color = Palette.accent
        case .alert: glyph = "!"; color = Palette.gold
        default: glyph = nil; color = .clear
        }
        if let glyph {
            for i in 0..<2 {
                let phase = (t * 0.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let p = CGPoint(x: body.maxX + s * 0.02 + CGFloat(phase) * s * 0.08 + CGFloat(sin(t * 3 + Double(i))) * s * 0.02,
                                y: body.minY + s * 0.02 - CGFloat(phase) * s * 0.25)
                c.draw(Text(glyph).font(.system(size: s * 0.15 * CGFloat(0.7 + phase * 0.5), weight: .heavy))
                        .foregroundColor(color.opacity(1 - phase)), at: p)
            }
        }
        if mood == .typing {
            // A keycap pops off for each recent key press (random letters — the real keys are never known).
            let letters = Array("ASDFJKLGHQWERTYUIOPZXCVBNM")
            for (i, age) in keyAges.enumerated() where age < 0.9 {
                let phase = CGFloat(age / 0.9)
                var rng = SplitMix64(seed: UInt64(i) &+ UInt64(max(0, t - age) * 1000))
                let side: CGFloat = rng.next() % 2 == 0 ? -1 : 1
                let spread = CGFloat(rng.next() % 100) / 100
                let p = CGPoint(x: body.midX + side * (body.width * (0.25 + 0.3 * spread)) * phase,
                                y: body.minY - s * 0.02 - phase * s * 0.3 + phase * phase * s * 0.12)
                let k = s * 0.085
                var cap = c
                cap.opacity = Double(1 - phase)
                cap.translateBy(x: p.x, y: p.y)
                cap.rotate(by: .radians(Double(side * phase) * 0.8))
                let rect = CGRect(x: -k / 2, y: -k / 2, width: k, height: k)
                cap.fill(Path(roundedRect: rect, cornerRadius: k * 0.22), with: .color(Color(hex: 0xF4F4F6)))
                cap.fill(Path(roundedRect: rect.insetBy(dx: k * 0.1, dy: k * 0.1).offsetBy(dx: 0, dy: -k * 0.05), cornerRadius: k * 0.16),
                         with: .color(.white))
                cap.draw(Text(String(letters[Int(rng.next() % UInt64(letters.count))]))
                            .font(.system(size: k * 0.5, weight: .bold, design: .rounded)).foregroundColor(Color(hex: 0x2A2D33)),
                         at: CGPoint(x: 0, y: -k * 0.04))
            }
            if heat >= 0.6 {
                // On fire.
                let flicker = CGFloat(sin(t * 14)) * 0.08
                c.draw(Text("🔥").font(.system(size: s * 0.16 * (1 + flicker))),
                       at: CGPoint(x: body.minX - s * 0.02, y: body.minY - s * 0.02))
            }
        }
        if mood == .thinking {
            // A thought bubble rising from the top corner, dots taking turns.
            for (x, y, r) in [(body.maxX - s * 0.02, body.minY - s * 0.01, s * 0.018),
                              (body.maxX + s * 0.02, body.minY - s * 0.06, s * 0.026)] {
                c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.9)))
            }
            let bubble = CGRect(x: body.maxX - s * 0.02, y: body.minY - s * 0.22, width: s * 0.26, height: s * 0.13)
            c.fill(Path(roundedRect: bubble, cornerRadius: bubble.height / 2), with: .color(.white.opacity(0.92)))
            for i in 0..<3 {
                let lift = CGFloat(max(0, sin(t * 6 - Double(i) * 0.8))) * s * 0.015
                c.fill(Path(ellipseIn: CGRect(x: bubble.minX + s * 0.045 + CGFloat(i) * s * 0.06, y: bubble.midY - s * 0.017 - lift,
                                              width: s * 0.034, height: s * 0.034)), with: .color(Color(hex: 0x16161A)))
            }
        }
        if mood == .celebrating {
            let colors = [Palette.accent, Palette.gold, Color(hex: 0xFF6FA5), Color(hex: 0x5B9CF6)]
            for i in 0..<10 {
                let phase = (t * 0.9 + Double(i) / 10).truncatingRemainder(dividingBy: 1)
                let a = Double(i) * 0.63
                let p = CGPoint(x: body.midX + CGFloat(cos(a * 3) * phase) * s * 0.45,
                                y: body.minY - s * 0.1 + CGFloat(phase * phase) * s * 0.5 - CGFloat(sin(a)) * s * 0.2)
                let r = s * 0.02
                c.fill(Path(roundedRect: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 3), cornerRadius: r / 2),
                       with: .color(colors[i % colors.count].opacity(1 - phase)))
            }
        }
        if mood == .burping {
            for i in 0..<3 {
                let phase = (t * 1.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let r = s * 0.025 * CGFloat(1 + phase)
                let p = CGPoint(x: body.midX + s * 0.1 + CGFloat(i) * s * 0.03, y: body.minY + body.height * 0.5 - CGFloat(phase) * s * 0.4)
                c.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.7 * (1 - phase))), lineWidth: 1)
            }
        }
    }
}

#Preview("Characters × moods") {
    let genome = PetGenome.hatch(seed: 7)
    return ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(96)), count: 5), spacing: 16) {
            ForEach(PetCharacter.allCases) { character in
                ForEach(Mood.allCases, id: \.self) { mood in
                    VStack {
                        GobView(mood: mood, genome: genome, stage: 0, size: 80, character: character)
                        Text("\(character.rawValue) \(mood.rawValue)").font(.caption2).foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(24)
    }
    .background(.black)
}
