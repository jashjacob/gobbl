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
    /// Mouth open, waiting: a file is being dragged over the notch.
    var anticipating = false
    /// Frame rate: full while something is happening, a trickle at rest (blinks, breathing).
    var lively = true
    /// A still frame (pet card export): no timeline, no motion.
    var frozen = false
    var look: () -> CGFloat = { 0 }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || frozen }

    private var restful: Bool { [.idle, .sleeping, .sleepy].contains(mood) && !anticipating }

    /// The collapsed notch shows Gob all day, so at rest it only redraws to
    /// blink (twice every 4.3 s) — continuous frames there cost ~5% CPU.
    private var schedule: GobSchedule {
        if reduceMotion && restful { return GobSchedule(kind: .still) }
        if restful && !lively { return GobSchedule(kind: mood == .sleeping ? .still : .blinks) }
        return GobSchedule(kind: .frames(restful ? 1.0 / 10 : 1.0 / 30))
    }

    var body: some View {
        TimelineView(schedule) { context in
            Canvas { g, canvasSize in
                GobPainter(mood: mood, hue: genome.species.hue, shiny: genome.shiny, stage: stage,
                           t: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate,
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

private struct GobPainter {
    let mood: Mood
    let hue: Double
    let shiny: Bool
    let stage: Int
    let t: Double
    let look: CGFloat
    let anticipating: Bool
    let extras: Bool

    private let ink = Color(hex: 0x16161A)

    func draw(in c: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)

        // Body motion: squash (+ wide/short, − tall/thin), bounce, sway, tilt.
        var squash = sin(t * 2.2) * 0.025
        var dx: CGFloat = 0, dy: CGFloat = 0, tilt = 0.0
        switch mood {
        case .dancing:
            squash = sin(t * 8) * 0.07
            dx = sin(t * 4) * s * 0.05
            tilt = sin(t * 4) * 0.12
        case .eating: squash = abs(sin(t * 14)) * 0.12
        case .burping: squash = -abs(sin(t * 10)) * 0.08
        case .celebrating:
            dy = -abs(sin(t * 7)) * s * 0.1
            squash = cos(t * 14) * 0.05
        case .sleeping: squash = sin(t * 1.2) * 0.04
        case .dizzy: tilt = sin(t * 6) * 0.2
        case .love: squash = sin(t * 5) * 0.04
        case .alert: dx = sin(t * 40) * s * 0.012
        default: break
        }
        if anticipating { squash = -0.07 + sin(t * 9) * 0.02 }

        let bw = s * 0.84 * (1 + squash), bh = s * 0.66 * (1 - squash)
        let base = CGPoint(x: s / 2 + dx, y: s * 0.96 + dy)
        let body = CGRect(x: base.x - bw / 2, y: base.y - bh, width: bw, height: bh)

        c.translateBy(x: base.x, y: base.y)
        c.rotate(by: .radians(tilt))
        c.translateBy(x: -base.x, y: -base.y)

        let light = Color(hue: hue, saturation: 0.5, brightness: 1)
        let dark = Color(hue: hue, saturation: 0.78, brightness: 0.8)

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
            c.fill(Path(ellipseIn: CGRect(x: body.midX + side * eyeDX * 1.55 - eyeR, y: eyeY + eyeR * 0.9,
                                          width: eyeR * 2, height: eyeR * 1.1)),
                   with: .color(Color(hex: 0xFF6FA5, alpha: 0.35)))
        }

        drawMouth(&c, center: CGPoint(x: body.midX, y: body.minY + bh * 0.68), bw: bw, bh: bh, s: s, line: line)

        if stage >= 2 { drawCrown(&c, body: body, s: s) }
        if shiny { drawSparkles(&c, body: body, s: s) }
        if extras { drawExtras(&c, body: body, s: s) }
    }

    private func drawAntenna(_ c: inout GraphicsContext, body: CGRect, s: CGFloat, light: Color, dark: Color) {
        let wiggle = sin(t * 3) * s * 0.04 + (mood == .dancing ? sin(t * 8) * s * 0.05 : 0)
        let root = CGPoint(x: body.midX, y: body.minY + 2)
        let droop: CGFloat = mood == .sleeping || mood == .sleepy ? s * 0.08 : 0
        let tip = CGPoint(x: body.midX + s * 0.06 + wiggle + droop, y: body.minY - s * 0.15 + droop)
        var stalk = Path()
        stalk.move(to: root)
        stalk.addQuadCurve(to: tip, control: CGPoint(x: body.midX - s * 0.03, y: body.minY - s * 0.08))
        c.stroke(stalk, with: .color(dark), style: StrokeStyle(lineWidth: max(1, s * 0.03), lineCap: .round))
        let r = s * 0.045
        if stage >= 1 {
            // Teen: the bobble glows.
            c.fill(Path(ellipseIn: CGRect(x: tip.x - r * 2, y: tip.y - r * 2, width: r * 4, height: r * 4)),
                   with: .color(light.opacity(0.25 + 0.1 * sin(t * 3))))
        }
        c.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)), with: .color(light))
    }

    private func drawEyes(_ c: inout GraphicsContext, center: CGPoint, dx: CGFloat, r: CGFloat, line: CGFloat) {
        let blink = t.truncatingRemainder(dividingBy: GobSchedule.blinkPeriod) < GobSchedule.blinkLength - 0.01
        let stroke = StrokeStyle(lineWidth: line, lineCap: .round)
        for side in [-1.0, 1.0] {
            let e = CGPoint(x: center.x + side * dx, y: center.y)
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
                let big: CGFloat = anticipating || mood == .alert || mood == .curious ? 1.25 : 1
                let lid: CGFloat = mood == .sleepy ? 0.55 : 1
                let w = r * 1.5 * big, h = r * 2 * big * lid
                let px = e.x + max(-1, min(1, look)) * r * 0.45
                c.fill(Path(ellipseIn: CGRect(x: px - w / 2, y: e.y - h / 2, width: w, height: h)), with: .color(ink))
                let g = w * 0.36
                c.fill(Path(ellipseIn: CGRect(x: px - w * 0.3, y: e.y - h * 0.38, width: g, height: g)), with: .color(.white))
            }
        }
    }

    private func drawMouth(_ c: inout GraphicsContext, center m: CGPoint, bw: CGFloat, bh: CGFloat, s: CGFloat, line: CGFloat) {
        let stroke = StrokeStyle(lineWidth: line, lineCap: .round)
        let mouthInk = Color(hex: 0x3A1020)
        switch mood {
        case _ where anticipating || mood == .eating:
            let w = bw * (anticipating ? 0.32 : 0.28)
            let h = anticipating ? bh * 0.24 : bh * (0.06 + abs(sin(t * 14)) * 0.16)
            c.fill(Path(ellipseIn: CGRect(x: m.x - w / 2, y: m.y - h / 2, width: w, height: h)), with: .color(mouthInk))
            if h > bh * 0.12 {
                // Tongue.
                c.fill(Path(ellipseIn: CGRect(x: m.x - w * 0.25, y: m.y + h * 0.05, width: w * 0.5, height: h * 0.4)),
                       with: .color(Color(hex: 0xFF7A9C)))
            }
        case .burping, .alert, .dizzy:
            let r = s * (mood == .burping ? 0.06 : 0.045)
            c.fill(Path(ellipseIn: CGRect(x: m.x - r, y: m.y - r, width: r * 2, height: r * 2)), with: .color(mouthInk))
        case .sleepy, .sleeping:
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

    private func drawCrown(_ c: inout GraphicsContext, body: CGRect, s: CGFloat) {
        let w = s * 0.2, h = s * 0.11
        let x = body.midX - body.width * 0.3, y = body.minY + s * 0.02
        var p = Path()
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x, y: y - h))
        p.addLine(to: CGPoint(x: x + w * 0.25, y: y - h * 0.5))
        p.addLine(to: CGPoint(x: x + w * 0.5, y: y - h * 1.1))
        p.addLine(to: CGPoint(x: x + w * 0.75, y: y - h * 0.5))
        p.addLine(to: CGPoint(x: x + w, y: y - h))
        p.addLine(to: CGPoint(x: x + w, y: y))
        p.closeSubpath()
        c.fill(p.applying(CGAffineTransform(translationX: x + w / 2, y: y).rotated(by: -0.25)
                .translatedBy(x: -(x + w / 2), y: -y)), with: .color(Palette.gold))
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

    /// Floating glyphs: z's, hearts, notes, confetti. Only at sizes where they read.
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
                let p = CGPoint(x: body.maxX - s * 0.04 + CGFloat(phase) * s * 0.08 + sin(t * 3 + Double(i)) * s * 0.02,
                                y: body.minY + s * 0.05 - CGFloat(phase) * s * 0.28)
                c.draw(Text(glyph).font(.system(size: s * 0.15 * (0.7 + phase * 0.5), weight: .heavy))
                        .foregroundColor(color.opacity(1 - phase)), at: p)
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
                let r = s * 0.025 * (1 + phase)
                let p = CGPoint(x: body.midX + s * 0.1 + CGFloat(i) * s * 0.03, y: body.minY + body.height * 0.6 - CGFloat(phase) * s * 0.4)
                c.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.7 * (1 - phase))), lineWidth: 1)
            }
        }
    }
}

#Preview("Moods") {
    let genome = PetGenome.hatch(seed: 7)
    return LazyVGrid(columns: Array(repeating: GridItem(.fixed(96)), count: 4), spacing: 16) {
        ForEach(Mood.allCases, id: \.self) { mood in
            VStack {
                GobView(mood: mood, genome: genome, stage: 2, size: 80)
                Text(mood.rawValue).font(.caption).foregroundStyle(.white)
            }
        }
    }
    .padding(24)
    .background(.black)
}
