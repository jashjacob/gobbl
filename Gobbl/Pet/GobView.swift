import GobblCore
import SwiftUI

/// Gob, drawn procedurally: a squishy gumdrop with an antenna, big eyes and a
/// stretchy mouth. Stand-in for the Rive character — every Mood gets a pose,
/// so swapping the renderer later doesn't change any call site.
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
    var look: () -> CGFloat = { 0 }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || frozen }

    private var restful: Bool { [.idle, .sleeping, .sleepy].contains(mood) && !anticipating }

    /// The collapsed notch shows Gob all day, so at rest it only redraws to
    /// blink (twice every 4.3 s) — continuous frames there cost ~5% CPU.
    private var schedule: GobSchedule {
        if time != nil || (reduceMotion && restful) { return GobSchedule(kind: .still) }
        if restful && !lively { return GobSchedule(kind: mood == .sleeping ? .still : .blinks) }
        // Collapsed-notch Gob is tiny and can stay "working" for as long as an
        // agent runs: 15 fps there is indistinguishable and half the cost.
        if !lively { return GobSchedule(kind: .frames(1.0 / 15)) }
        return GobSchedule(kind: .frames(restful ? 1.0 / 10 : 1.0 / 30))
    }

    var body: some View {
        let character = self.character ?? PetModel.shared.character
        let colors = (skin ?? PetModel.shared.skin).map(GobColors.init)
        TimelineView(schedule) { context in
            Canvas { g, canvasSize in
                GobPainter(mood: mood, hue: genome.species.hue, shiny: genome.shiny, stage: stage, hat: hat, character: character,
                           colors: colors,
                           t: time ?? (reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate),
                           look: look(), anticipating: anticipating, extras: size >= 40)
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
    let anticipating: Bool
    let extras: Bool

    /// Face colour: dark on the blob, glowing phosphor on the retro screen.
    private var ink: Color {
        character == .retro ? (colors?.glow ?? Palette.accent) : (colors?.face ?? Color(hex: 0x16161A))
    }

    private var cheekColor: Color { colors?.cheeks?.opacity(0.4) ?? Color(hex: 0xFF6FA5, alpha: 0.35) }

    private func s(_ x: Double) -> CGFloat { CGFloat(x) }

    func draw(in c: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)

        // Body motion: squash (+ wide/short, − tall/thin), bounce, sway, tilt.
        var squash = sin(t * 2.2) * 0.025
        var dx: CGFloat = 0, dy: CGFloat = 0, tilt = 0.0
        switch mood {
        case .dancing:
            squash = sin(t * 8) * 0.07
            dx = CGFloat(sin(t * 4)) * s * 0.05
            tilt = sin(t * 4) * 0.12
        case .eating: squash = abs(sin(t * 14)) * 0.12
        case .burping: squash = -abs(sin(t * 10)) * 0.08
        case .celebrating:
            dy = -CGFloat(abs(sin(t * 7))) * s * 0.1
            squash = cos(t * 14) * 0.05
        case .sleeping: squash = sin(t * 1.2) * 0.04
        case .dizzy: tilt = sin(t * 6) * 0.2
        case .love: squash = sin(t * 5) * 0.04
        case .alert: dx = CGFloat(sin(t * 40)) * s * 0.012
        case .working: dy = -CGFloat(abs(sin(t * 12))) * s * 0.012
        case .sweaty: dx = CGFloat(sin(t * 30)) * s * 0.006
        default: break
        }
        if anticipating { squash = -0.07 + sin(t * 9) * 0.02 }

        if character == .retro {
            drawRetro(&c, s: s, squash: squash, dx: dx, dy: dy, tilt: tilt)
            return
        }

        let bw = s * 0.84 * CGFloat(1 + squash), bh = s * 0.66 * CGFloat(1 - squash)
        let base = CGPoint(x: s / 2 + dx, y: s * 0.96 + dy)
        let body = CGRect(x: base.x - bw / 2, y: base.y - bh, width: bw, height: bh)

        c.translateBy(x: base.x, y: base.y)
        c.rotate(by: .radians(tilt))
        c.translateBy(x: -base.x, y: -base.y)

        let light = colors?.top ?? Color(hue: hue, saturation: 0.5, brightness: 1)
        let dark = colors?.bottom ?? Color(hue: hue, saturation: 0.78, brightness: 0.8)

        drawAntenna(&c, body: body, s: s, light: light, dark: dark)

        let shape = Path(roundedRect: body, cornerSize: CGSize(width: bw * 0.5, height: bh * 0.62), style: .continuous)
        c.fill(shape, with: .linearGradient(Gradient(colors: [light, dark]),
                                            startPoint: CGPoint(x: body.midX, y: body.minY),
                                            endPoint: CGPoint(x: body.midX, y: body.maxY)))
        // Soft highlight, top left.
        c.fill(Path(ellipseIn: CGRect(x: body.minX + bw * 0.16, y: body.minY + bh * 0.1, width: bw * 0.26, height: bh * 0.16)),
               with: .color(.white.opacity(0.35)))

        let eyeY = body.minY + bh * 0.42
        let eyeDX = bw * 0.19
        let eyeR = s * 0.075
        let line = max(1, s * 0.035)
        drawEyes(&c, center: CGPoint(x: body.midX, y: eyeY), dx: eyeDX, r: eyeR, line: line)

        // Cheeks.
        for side in [-1.0, 1.0] {
            c.fill(Path(ellipseIn: CGRect(x: body.midX + CGFloat(side) * eyeDX * 1.55 - eyeR, y: eyeY + eyeR * 0.9,
                                          width: eyeR * 2, height: eyeR * 1.1)),
                   with: .color(cheekColor))
        }

        drawMouth(&c, center: CGPoint(x: body.midX, y: body.minY + bh * 0.68), bw: bw, bh: bh, s: s, line: line)

        if hat != .none { drawHat(&c, body: body, s: s, eyeY: eyeY, eyeDX: eyeDX, eyeR: eyeR) }
        if shiny { drawSparkles(&c, body: body, s: s) }
        if mood == .sweaty { drawSweat(&c, body: body, s: s) }
        if extras { drawExtras(&c, body: body, s: s) }
    }

    private func drawAntenna(_ c: inout GraphicsContext, body: CGRect, s: CGFloat, light: Color, dark: Color) {
        let spin = mood == .working ? CGFloat(sin(t * 14)) * s * 0.03 : 0
        let wiggle = CGFloat(sin(t * 3)) * s * 0.04 + (mood == .dancing ? CGFloat(sin(t * 8)) * s * 0.05 : 0) + spin
        let root = CGPoint(x: body.midX, y: body.minY + 2)
        let droop: CGFloat = mood == .sleeping || mood == .sleepy ? s * 0.08 : 0
        let tip = CGPoint(x: body.midX + s * 0.06 + wiggle + droop, y: body.minY - s * 0.15 + droop)
        var stalk = Path()
        stalk.move(to: root)
        stalk.addQuadCurve(to: tip, control: CGPoint(x: body.midX - s * 0.03, y: body.minY - s * 0.08))
        c.stroke(stalk, with: .color(dark), style: StrokeStyle(lineWidth: max(1, s * 0.03), lineCap: .round))
        let r = s * 0.045
        if stage >= 1 || mood == .working {
            // Teen (or thinking): the bobble glows.
            c.fill(Path(ellipseIn: CGRect(x: tip.x - r * 2, y: tip.y - r * 2, width: r * 4, height: r * 4)),
                   with: .color(light.opacity(0.25 + 0.1 * sin(t * (mood == .working ? 10 : 3)))))
        }
        c.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)), with: .color(light))
    }

    private func drawEyes(_ c: inout GraphicsContext, center: CGPoint, dx: CGFloat, r: CGFloat, line: CGFloat) {
        let blink = t.truncatingRemainder(dividingBy: GobSchedule.blinkPeriod) < GobSchedule.blinkLength - 0.01
        let stroke = StrokeStyle(lineWidth: line, lineCap: .round)
        for side in [-1.0, 1.0] {
            let e = CGPoint(x: center.x + CGFloat(side) * dx, y: center.y)
            switch mood {
            case .sleeping:
                var p = Path()
                p.move(to: CGPoint(x: e.x - r, y: e.y))
                p.addQuadCurve(to: CGPoint(x: e.x + r, y: e.y), control: CGPoint(x: e.x, y: e.y + r * 0.9))
                c.stroke(p, with: .color(ink), style: stroke)
            case .happy, .love, .celebrating, .dancing:
                var p = Path()
                p.move(to: CGPoint(x: e.x - r, y: e.y + r * 0.3))
                p.addQuadCurve(to: CGPoint(x: e.x + r, y: e.y + r * 0.3), control: CGPoint(x: e.x, y: e.y - r * 1.2))
                c.stroke(p, with: .color(ink), style: stroke)
            case .dizzy:
                var p = Path()
                p.move(to: CGPoint(x: e.x - r * 0.8, y: e.y - r * 0.8))
                p.addLine(to: CGPoint(x: e.x + r * 0.8, y: e.y + r * 0.8))
                p.move(to: CGPoint(x: e.x + r * 0.8, y: e.y - r * 0.8))
                p.addLine(to: CGPoint(x: e.x - r * 0.8, y: e.y + r * 0.8))
                c.stroke(p, with: .color(ink), style: stroke)
            default:
                if blink {
                    var p = Path()
                    p.move(to: CGPoint(x: e.x - r, y: e.y))
                    p.addLine(to: CGPoint(x: e.x + r, y: e.y))
                    c.stroke(p, with: .color(ink), style: stroke)
                    continue
                }
                let big: CGFloat = anticipating || mood == .alert || mood == .curious || mood == .sweaty ? 1.25 : 1
                let lid: CGFloat = mood == .sleepy ? 0.55 : (mood == .working ? 0.8 : 1)
                let w = r * 1.5 * big, h = r * 2 * big * lid
                // Working: eyes down at the "keyboard", flicking side to side.
                let lookX = mood == .working ? CGFloat(sin(t * 5)) * 0.6 : max(-1, min(1, look))
                let px = e.x + lookX * r * 0.45
                let py = e.y + (mood == .working ? r * 0.3 : 0)
                let eyeRect = CGRect(x: px - w / 2, y: py - h / 2, width: w, height: h)
                if character == .retro {
                    // Chunky phosphor pixels, no glint.
                    c.fill(Path(roundedRect: eyeRect, cornerRadius: w * 0.25), with: .color(ink))
                } else {
                    c.fill(Path(ellipseIn: eyeRect), with: .color(ink))
                    let g = w * 0.36
                    c.fill(Path(ellipseIn: CGRect(x: px - w * 0.3, y: py - h * 0.38, width: g, height: g)), with: .color(.white))
                }
            }
        }
    }

    private func drawMouth(_ c: inout GraphicsContext, center m: CGPoint, bw: CGFloat, bh: CGFloat, s: CGFloat, line: CGFloat) {
        let stroke = StrokeStyle(lineWidth: line, lineCap: .round)
        let mouthInk = character == .retro ? ink : Color(hex: 0x3A1020)
        switch mood {
        case _ where anticipating || mood == .eating:
            let w = bw * (anticipating ? 0.32 : 0.28)
            let h = anticipating ? bh * 0.24 : bh * CGFloat(0.06 + abs(sin(t * 14)) * 0.16)
            c.fill(Path(ellipseIn: CGRect(x: m.x - w / 2, y: m.y - h / 2, width: w, height: h)), with: .color(mouthInk))
            if character == .gob, h > bh * 0.12 {
                // Tongue.
                c.fill(Path(ellipseIn: CGRect(x: m.x - w * 0.25, y: m.y + h * 0.05, width: w * 0.5, height: h * 0.4)),
                       with: .color(Color(hex: 0xFF7A9C)))
            }
        case .burping, .alert, .dizzy:
            let r = s * (mood == .burping ? 0.06 : 0.045)
            c.fill(Path(ellipseIn: CGRect(x: m.x - r, y: m.y - r, width: r * 2, height: r * 2)), with: .color(mouthInk))
        case .sweaty:
            // Wobbly worried line.
            var p = Path()
            p.move(to: CGPoint(x: m.x - bw * 0.1, y: m.y))
            for i in 1...4 {
                p.addLine(to: CGPoint(x: m.x - bw * 0.1 + bw * 0.05 * CGFloat(i), y: m.y + (i.isMultiple(of: 2) ? 0 : bh * 0.04)))
            }
            c.stroke(p, with: .color(ink), style: stroke)
        case .sleepy, .sleeping, .working:
            var p = Path()
            p.move(to: CGPoint(x: m.x - bw * 0.05, y: m.y))
            p.addLine(to: CGPoint(x: m.x + bw * 0.05, y: m.y))
            c.stroke(p, with: .color(ink), style: stroke)
        default:
            let wide: CGFloat = [.happy, .love, .celebrating, .dancing].contains(mood) ? 0.13 : 0.08
            var p = Path()
            p.move(to: CGPoint(x: m.x - bw * wide, y: m.y - bh * 0.02))
            p.addQuadCurve(to: CGPoint(x: m.x + bw * wide, y: m.y - bh * 0.02),
                           control: CGPoint(x: m.x, y: m.y + bh * (wide > 0.1 ? 0.14 : 0.08)))
            c.stroke(p, with: .color(ink), style: stroke)
        }
    }

    // MARK: Retro computer

    /// A little 80s desktop: beige-ish case tinted by species, a CRT screen
    /// with a glowing pixel face, vents, a floppy slot it eats files through,
    /// and a drive light that blinks while it's busy. Deliberately generic —
    /// no Apple logo, no Macintosh silhouette, no Happy Mac face.
    private func drawRetro(_ c: inout GraphicsContext, s: CGFloat, squash: Double, dx: CGFloat, dy: CGFloat, tilt: Double) {
        // A box squashes less than a blob.
        let sq = CGFloat(squash) * 0.45
        let w = s * 0.7 * (1 + sq), h = s * 0.8 * (1 - sq)
        let base = CGPoint(x: s / 2 + dx, y: s * 0.93 + dy)
        let casing = CGRect(x: base.x - w / 2, y: base.y - h, width: w, height: h)
        c.translateBy(x: base.x, y: base.y)
        c.rotate(by: .radians(tilt))
        c.translateBy(x: -base.x, y: -base.y)

        let light = colors?.top ?? Color(hue: hue, saturation: 0.14, brightness: 0.96)
        let dark = colors?.bottom ?? Color(hue: hue, saturation: 0.2, brightness: 0.8)
        let shade = colors.map { $0.bottom.opacity(0.9) } ?? Color(hue: hue, saturation: 0.25, brightness: 0.55)

        // Feet.
        for side in [-1.0, 1.0] {
            c.fill(Path(roundedRect: CGRect(x: casing.midX + CGFloat(side) * w * 0.3 - w * 0.1, y: casing.maxY - s * 0.01,
                                            width: w * 0.2, height: s * 0.05), cornerRadius: s * 0.02),
                   with: .color(shade))
        }
        // Case, with a light edge.
        let shell = Path(roundedRect: casing, cornerRadius: w * 0.13, style: .continuous)
        c.fill(shell, with: .linearGradient(Gradient(colors: [light, dark]),
                                            startPoint: CGPoint(x: casing.midX, y: casing.minY),
                                            endPoint: CGPoint(x: casing.midX, y: casing.maxY)))
        c.stroke(shell, with: .color(.white.opacity(0.35)), lineWidth: max(0.5, s * 0.008))

        // Recessed CRT.
        let screen = CGRect(x: casing.minX + w * 0.13, y: casing.minY + h * 0.09, width: w * 0.74, height: h * 0.52)
        c.fill(Path(roundedRect: screen.insetBy(dx: -w * 0.035, dy: -w * 0.035), cornerRadius: w * 0.1, style: .continuous),
               with: .color(shade.opacity(0.55)))
        c.fill(Path(roundedRect: screen, cornerRadius: w * 0.08, style: .continuous),
               with: .radialGradient(Gradient(colors: [Color(hex: 0x1F3A28), Color(hex: 0x0A120D)]),
                                     center: CGPoint(x: screen.midX, y: screen.midY), startRadius: 0, endRadius: screen.width * 0.7))

        // Phosphor face, glowing at sizes where the glow reads.
        let eyeY = screen.minY + screen.height * 0.4
        let eyeDX = screen.width * 0.2
        let eyeR = screen.width * 0.075
        let line = max(1, s * 0.03)
        var face = c
        if s >= 40 { face.addFilter(.shadow(color: ink.opacity(0.8), radius: s * 0.02)) }
        drawEyes(&face, center: CGPoint(x: screen.midX, y: eyeY), dx: eyeDX, r: eyeR, line: line)
        drawMouth(&face, center: CGPoint(x: screen.midX, y: screen.minY + screen.height * 0.73),
                  bw: screen.width, bh: screen.height, s: s * 0.75, line: line)
        for side in [-1.0, 1.0] {
            c.fill(Path(roundedRect: CGRect(x: screen.midX + CGFloat(side) * eyeDX * 1.6 - eyeR, y: eyeY + eyeR * 1.3,
                                            width: eyeR * 2, height: eyeR * 0.8), cornerRadius: eyeR * 0.3),
                   with: .color(cheekColor))
        }
        if s >= 40 {
            var y = screen.minY + s * 0.01
            while y < screen.maxY - s * 0.005 {
                c.fill(Path(CGRect(x: screen.minX + w * 0.02, y: y, width: screen.width - w * 0.04, height: max(0.5, s * 0.004))),
                       with: .color(.black.opacity(0.22)))
                y += s * 0.018
            }
        }
        c.fill(Path(ellipseIn: CGRect(x: screen.minX + screen.width * 0.08, y: screen.minY + screen.height * 0.06,
                                      width: screen.width * 0.3, height: screen.height * 0.14)),
               with: .color(.white.opacity(0.07)))

        // Chin: vents, the floppy slot (it eats files through it) and the drive light.
        let slot = CGRect(x: casing.midX - w * 0.02, y: casing.minY + h * 0.76, width: w * 0.34, height: max(1.5, h * 0.035))
        if mood == .eating || anticipating {
            let phase = anticipating ? 0 : CGFloat((t * 1.4).truncatingRemainder(dividingBy: 1))
            let side = w * 0.22
            let disk = CGRect(x: slot.midX - side / 2, y: slot.midY - side * (1 - phase), width: side, height: side * (1 - phase))
            c.fill(Path(roundedRect: disk, cornerRadius: side * 0.06), with: .color(Color(hex: 0x3E6BE0)))
            c.fill(Path(CGRect(x: disk.minX + side * 0.25, y: disk.minY, width: side * 0.5, height: min(disk.height, side * 0.3))),
                   with: .color(Color(hex: 0xC9D2E0)))
        }
        c.fill(Path(roundedRect: slot, cornerRadius: slot.height / 2), with: .color(.black.opacity(0.6)))
        let busy = [.eating, .working, .burping].contains(mood)
        let led = CGRect(x: slot.maxX - w * 0.07, y: slot.maxY + h * 0.035, width: w * 0.05, height: max(1, h * 0.022))
        c.fill(Path(roundedRect: led, cornerRadius: led.height / 2),
               with: .color(busy && sin(t * 20) > -0.3 ? Palette.accent : shade.opacity(0.6)))
        for i in 0..<3 {
            c.fill(Path(roundedRect: CGRect(x: casing.minX + w * 0.13 + CGFloat(i) * w * 0.05, y: slot.minY - h * 0.01,
                                            width: max(1, w * 0.018), height: h * 0.08), cornerRadius: 1),
                   with: .color(shade.opacity(0.45)))
        }

        if hat != .none { drawHat(&c, body: casing, s: s, eyeY: eyeY, eyeDX: eyeDX, eyeR: eyeR) }
        if shiny { drawSparkles(&c, body: casing, s: s) }
        if mood == .sweaty { drawSweat(&c, body: casing, s: s) }
        if extras { drawExtras(&c, body: casing, s: s) }
    }

    // MARK: Hats

    private func drawHat(_ c: inout GraphicsContext, body: CGRect, s: CGFloat, eyeY: CGFloat, eyeDX: CGFloat, eyeR: CGFloat) {
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
            let p = CGPoint(x: cx - w * 0.3, y: top + s * 0.06)
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
            let brim = CGRect(x: body.minX + w * 0.14, y: top + s * 0.02, width: w * 0.72, height: s * 0.07)
            var dome = Path()
            dome.move(to: CGPoint(x: brim.minX + s * 0.01, y: brim.minY + 2))
            if red {
                dome.addQuadCurve(to: CGPoint(x: brim.maxX + s * 0.12, y: brim.minY - s * 0.1),
                                  control: CGPoint(x: cx, y: top - s * 0.32))
                dome.addLine(to: CGPoint(x: brim.maxX - s * 0.01, y: brim.minY + 2))
            } else {
                dome.addQuadCurve(to: CGPoint(x: brim.maxX - s * 0.01, y: brim.minY + 2),
                                  control: CGPoint(x: cx, y: top - s * 0.26))
            }
            dome.closeSubpath()
            c.fill(dome, with: .color(red ? Color(hex: 0xE0343B) : Color(hex: 0x3E6BE0)))
            c.fill(Path(roundedRect: brim, cornerRadius: brim.height / 2),
                   with: .color(red ? .white : Color(hex: 0x2B4FB5)))
            let pom = red ? CGPoint(x: brim.maxX + s * 0.12, y: brim.minY - s * 0.1) : CGPoint(x: cx, y: top - s * 0.11)
            c.fill(Path(ellipseIn: CGRect(x: pom.x - s * 0.045, y: pom.y - s * 0.045, width: s * 0.09, height: s * 0.09)),
                   with: .color(.white))
        case .headphones:
            var band = Path()
            band.move(to: CGPoint(x: body.minX + w * 0.04, y: top + body.height * 0.4))
            band.addQuadCurve(to: CGPoint(x: body.maxX - w * 0.04, y: top + body.height * 0.4),
                              control: CGPoint(x: cx, y: top - s * 0.2))
            c.stroke(band, with: .color(Color(hex: 0x2A2D33)), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
            for side in [-1.0, 1.0] {
                let x = side < 0 ? body.minX - s * 0.02 : body.maxX - s * 0.08
                c.fill(Path(roundedRect: CGRect(x: x, y: top + body.height * 0.3, width: s * 0.1, height: s * 0.17), cornerRadius: s * 0.04),
                       with: .color(Palette.accent))
            }
        case .sunglasses:
            for side in [-1.0, 1.0] {
                let e = CGPoint(x: cx + CGFloat(side) * eyeDX, y: eyeY)
                c.fill(Path(roundedRect: CGRect(x: e.x - eyeR * 1.35, y: e.y - eyeR * 0.95, width: eyeR * 2.7, height: eyeR * 1.9),
                            cornerRadius: eyeR * 0.7), with: .color(Color(hex: 0x111114)))
                c.fill(Path(ellipseIn: CGRect(x: e.x - eyeR * 0.9, y: e.y - eyeR * 0.6, width: eyeR * 0.7, height: eyeR * 0.35)),
                       with: .color(.white.opacity(0.5)))
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: cx - eyeDX + eyeR * 1.3, y: eyeY - eyeR * 0.3))
            bridge.addLine(to: CGPoint(x: cx + eyeDX - eyeR * 1.3, y: eyeY - eyeR * 0.3))
            c.stroke(bridge, with: .color(Color(hex: 0x111114)), lineWidth: max(1, s * 0.02))
        case .halo:
            let bob = CGFloat(sin(t * 2)) * s * 0.01
            c.stroke(Path(ellipseIn: CGRect(x: cx - w * 0.28, y: top - s * 0.2 + bob, width: w * 0.56, height: s * 0.09)),
                     with: .color(Palette.gold), lineWidth: max(1.5, s * 0.03))
        case .crown:
            let cw = s * 0.24, ch = s * 0.13
            let x = cx - cw / 2, y = top + s * 0.03
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
            let p = CGPoint(x: cx + w * 0.3, y: top + s * 0.07)
            let r = s * 0.04
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi + t * 0.5
                c.fill(Path(ellipseIn: CGRect(x: p.x + CGFloat(cos(a)) * r - r, y: p.y + CGFloat(sin(a)) * r - r, width: r * 2, height: r * 2)),
                       with: .color(Color(hex: 0xFFB3D1)))
            }
            c.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.7, y: p.y - r * 0.7, width: r * 1.4, height: r * 1.4)), with: .color(Palette.gold))
        case .pumpkin:
            let pw = s * 0.3, ph = s * 0.2
            let rect = CGRect(x: cx - pw / 2, y: top - ph * 0.55, width: pw, height: ph)
            for i in 0..<3 {
                let segW = pw * 0.5
                let x = rect.minX + CGFloat(i) * pw * 0.25
                c.fill(Path(ellipseIn: CGRect(x: x, y: rect.minY, width: segW, height: ph)),
                       with: .color(i == 1 ? Color(hex: 0xFF8A1F) : Color(hex: 0xE8700C)))
            }
            c.fill(Path(roundedRect: CGRect(x: cx - s * 0.015, y: rect.minY - s * 0.06, width: s * 0.03, height: s * 0.07), cornerRadius: s * 0.01),
                   with: .color(Color(hex: 0x4E7A2A)))
        case .diya:
            let bowl = CGRect(x: cx - s * 0.12, y: top - s * 0.05, width: s * 0.24, height: s * 0.09)
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
            let p = CGPoint(x: body.midX + CGFloat(cos(a)) * body.width * 0.55,
                            y: body.midY + CGFloat(sin(a)) * body.height * 0.6)
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
        let p = CGPoint(x: body.maxX - body.width * 0.12, y: body.minY + body.height * (0.15 + 0.4 * phase))
        let r = s * 0.05
        var drop = Path()
        drop.move(to: CGPoint(x: p.x, y: p.y - r * 1.6))
        drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: CGPoint(x: p.x + r * 1.6, y: p.y + r))
        drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r * 1.6), control: CGPoint(x: p.x - r * 1.6, y: p.y + r))
        c.fill(drop, with: .color(Color(hex: 0x7CC8FF).opacity(Double(1 - phase * 0.6))))
    }

    /// Floating glyphs: z's, hearts, notes, confetti, typing dots. Only at sizes where they read.
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
                let p = CGPoint(x: body.maxX - s * 0.04 + CGFloat(phase) * s * 0.08 + CGFloat(sin(t * 3 + Double(i))) * s * 0.02,
                                y: body.minY + s * 0.05 - CGFloat(phase) * s * 0.28)
                c.draw(Text(glyph).font(.system(size: s * 0.15 * CGFloat(0.7 + phase * 0.5), weight: .heavy))
                        .foregroundColor(color.opacity(1 - phase)), at: p)
            }
        }
        if mood == .working {
            // A thought bubble with three typing dots.
            let bubble = CGRect(x: body.maxX - s * 0.1, y: body.minY - s * 0.12, width: s * 0.26, height: s * 0.13)
            c.fill(Path(roundedRect: bubble, cornerRadius: bubble.height / 2), with: .color(.white.opacity(0.92)))
            for i in 0..<3 {
                let lift = CGFloat(max(0, sin(t * 8 - Double(i) * 0.8))) * s * 0.015
                c.fill(Path(ellipseIn: CGRect(x: bubble.minX + s * 0.045 + CGFloat(i) * s * 0.06, y: bubble.midY - s * 0.017 - lift,
                                              width: s * 0.034, height: s * 0.034)), with: .color(ink))
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
                let p = CGPoint(x: body.midX + s * 0.1 + CGFloat(i) * s * 0.03, y: body.minY + body.height * 0.6 - CGFloat(phase) * s * 0.4)
                c.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.7 * (1 - phase))), lineWidth: 1)
            }
        }
    }
}

#Preview("Moods") {
    let genome = PetGenome.hatch(seed: 7)
    return LazyVGrid(columns: Array(repeating: GridItem(.fixed(96)), count: 5), spacing: 16) {
        ForEach(Mood.allCases, id: \.self) { mood in
            VStack {
                GobView(mood: mood, genome: genome, stage: 2, size: 80)
                Text(mood.rawValue).font(.caption).foregroundStyle(.white)
            }
        }
        ForEach(Mood.allCases, id: \.self) { mood in
            VStack {
                GobView(mood: mood, genome: genome, stage: 0, size: 80, character: .retro)
                Text("retro " + mood.rawValue).font(.caption).foregroundStyle(.white)
            }
        }
        ForEach(Hat.allCases) { hat in
            VStack {
                GobView(mood: .happy, genome: genome, stage: 0, size: 80, hat: hat)
                Text(hat.title).font(.caption).foregroundStyle(.white)
            }
        }
    }
    .padding(24)
    .background(.black)
}
