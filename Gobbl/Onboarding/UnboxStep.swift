import GobblCore
import SwiftUI

/// First run: a shipping box arrives, the flaps open, the computer rises out
/// and its screen switches on. Then the reveal: colour, rarity, model, name.
struct UnboxStep: View {
    let next: () -> Void
    @State private var pet = PetModel.shared
    @State private var openedAt: Date?
    @State private var revealed = false
    @AppStorage(PetModel.Keys.name) private var name = "Gob"

    /// Seconds from "Open the box" to the face appearing.
    static let duration = 3.8

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation) { context in
                let e = openedAt.map { context.date.timeIntervalSince($0) } ?? -1
                UnboxScene(elapsed: e, t: context.date.timeIntervalSinceReferenceDate, pet: pet)
            }
            .frame(height: 250)
            .onTapGesture { if revealed { pet.send(.petted) } }

            if !revealed {
                Text(openedAt == nil ? "Your new computer has arrived." : "Unboxing…")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("A tiny computer wants to move into your notch.")
                    .font(.system(size: 13.5)).foregroundStyle(Palette.textSecondary)
                Button("Open the box") { open() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(openedAt != nil)
                    .padding(.top, 6)
            } else {
                HStack(spacing: 10) {
                    Text("It's a \(pet.genome.shiny ? "limited-edition " : "")\(pet.genome.species.displayName) \(pet.character.title)!")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    RarityChip(rarity: pet.genome.rarity, shiny: pet.genome.shiny)
                }
                Text(rarityLine).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                Picker("", selection: Binding(get: { pet.character }, set: { pet.character = $0 })) {
                    ForEach(PetCharacter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                HStack(spacing: 10) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 170)
                    Button("That's my computer", action: next)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
        }
    }

    private var rarityLine: String {
        if pet.genome.shiny { return "Only 1 in 100 ship as limited editions. Show it off." }
        switch pet.genome.species.rarity {
        case .legendary: return "1 in 100 boxes. You lucky thing."
        case .rare: return "Only 1 in 20 boxes have this colour."
        case .uncommon: return "1 in 10 boxes. Nice."
        case .common: return "Give it a name. You can pet it any time."
        }
    }

    private func open() {
        openedAt = Date()
        Task {
            try? await Task.sleep(for: .seconds(Self.duration))
            withAnimation(.gob) { revealed = true }
            pet.send(.celebrate)
        }
    }
}

/// The box and the computer at `elapsed` seconds after opening (−1: not opened yet).
struct UnboxScene: View {
    let elapsed: Double
    let t: Double
    let pet: PetModel

    var body: some View {
        let e = elapsed
        let flaps = e < 0 ? 0 : min(1, e / 0.6)
        let rise = e < 0 ? 0 : max(0, min(1, (e - 0.7) / 0.8))
        let boot = e < 0 ? 0 : max(0, min(1, (e - 1.5) / 2.3))
        let boxFade = e < 0 ? 1 : 1 - max(0, min(1, (e - 3.3) / 0.5))
        // Waiting: the box wiggles now and then. Opening: it jolts.
        let wobble = e < 0 ? sin(t * 9) * 0.05 * max(0, sin(t * 1.3)) : (e < 0.6 ? sin(e * 60) * 0.04 : 0)
        // Fixed stage 260×250: the box sits on the floor (y 110–250, its front
        // starts at y 155); the computer rises from inside it to stand above it,
        // then settles to the centre once the box has gone.
        let settle = e < 0 ? 0 : max(0, min(1, (e - 3.3) / 0.5))
        let petY = 215 - CGFloat(rise) * 135 + CGFloat(settle) * 45
        ZStack {
            GobView(mood: boot < 1 ? .idle : pet.mood, genome: pet.genome, stage: 0, size: 150, hat: .none,
                    boot: boot < 1 ? boot : nil, look: { pet.look })
                .position(x: 130, y: petY)
                .opacity(e < 0.6 ? 0 : 1)
            BoxShape(flaps: flaps, t: t, peanuts: e >= 0.4 && e < 2.2 ? (e - 0.4) : nil)
                .frame(width: 220, height: 140)
                .rotationEffect(.radians(wobble), anchor: .bottom)
                .position(x: 130, y: 180)
                .opacity(boxFade)
        }
        .frame(width: 260, height: 250)
        .clipped()
    }
}

/// A cardboard shipping box, front view: tape, a label, THIS SIDE UP arrows,
/// a FRAGILE stamp, and top flaps that swing open.
struct BoxShape: View {
    let flaps: Double
    let t: Double
    /// Seconds since the peanuts started popping, or nil.
    let peanuts: Double?

    var body: some View {
        Canvas { c, size in
            let w = size.width, h = size.height
            let top = h * 0.32
            let front = CGRect(x: w * 0.06, y: top, width: w * 0.88, height: h - top)
            let f = CGFloat(flaps)
            let dark = Color(hex: 0xA8743F), mid = Color(hex: 0xC8914F), light = Color(hex: 0xDDAA6A)

            // Back flaps (seen through the open top).
            if f > 0.05 {
                c.fill(Path(CGRect(x: front.minX + w * 0.04, y: top - h * 0.05 * f, width: front.width - w * 0.08, height: h * 0.05 * f)),
                       with: .color(dark))
            }
            // Packing peanuts popping out.
            if let peanuts {
                for i in 0..<9 {
                    let seed = Double(i) * 1.7
                    let life = peanuts - Double(i) * 0.08
                    guard life > 0 else { continue }
                    let x = front.midX + CGFloat(sin(seed) * 70) * CGFloat(min(1, life))
                    let y = top - CGFloat(life * 160 - life * life * 90) + 10
                    c.fill(Path(roundedRect: CGRect(x: x - 5, y: y - 3, width: 10, height: 6), cornerRadius: 3),
                           with: .color(Color(hex: 0xF4EEDC).opacity(max(0, 1 - life / 1.8))))
                }
            }
            // Front.
            c.fill(Path(roundedRect: front, cornerRadius: 6), with: .linearGradient(Gradient(colors: [light, mid]),
                                                                                   startPoint: CGPoint(x: 0, y: front.minY),
                                                                                   endPoint: CGPoint(x: 0, y: front.maxY)))
            c.stroke(Path(roundedRect: front, cornerRadius: 6), with: .color(dark.opacity(0.6)), lineWidth: 1.5)
            // Front flaps: closed they lie flat on top; opening, they swing up and out.
            for side in [-1.0, 1.0] {
                let s = CGFloat(side)
                let inner = CGPoint(x: front.midX, y: top)
                let outer = CGPoint(x: s < 0 ? front.minX : front.maxX, y: top)
                let lift = h * 0.3 * f
                let flare = w * 0.12 * f * s
                var flap = Path()
                flap.move(to: outer)
                flap.addLine(to: inner)
                flap.addLine(to: CGPoint(x: inner.x + flare * 0.3, y: top - lift - h * 0.02 * (1 - f)))
                flap.addLine(to: CGPoint(x: outer.x + flare, y: top - lift * 0.9 - h * 0.02 * (1 - f)))
                flap.closeSubpath()
                c.fill(flap, with: .color(f > 0.05 ? dark : light))
                c.stroke(flap, with: .color(dark.opacity(0.6)), lineWidth: 1)
            }
            if f < 0.05 {
                // Tape across the closed top and down the front.
                c.fill(Path(CGRect(x: front.midX - 9, y: top - h * 0.02, width: 18, height: front.height * 0.42)),
                       with: .color(Color(hex: 0xE9CF94).opacity(0.9)))
            }
            // Label and markings.
            let label = CGRect(x: front.minX + front.width * 0.1, y: front.minY + front.height * 0.46, width: front.width * 0.42, height: front.height * 0.36)
            c.fill(Path(roundedRect: label, cornerRadius: 4), with: .color(.white.opacity(0.92)))
            c.draw(Text("gobbl").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(Color(hex: 0x2A2D33)),
                   at: CGPoint(x: label.midX, y: label.midY - 7))
            c.draw(Text("1 × tiny computer").font(.system(size: 8.5, weight: .semibold)).foregroundColor(Color(hex: 0x6B6F78)),
                   at: CGPoint(x: label.midX, y: label.midY + 11))
            c.draw(Text("↑↑").font(.system(size: 15, weight: .heavy)).foregroundColor(dark),
                   at: CGPoint(x: front.maxX - front.width * 0.16, y: front.minY + front.height * 0.3))
            c.draw(Text("THIS SIDE UP").font(.system(size: 6.5, weight: .bold)).foregroundColor(dark),
                   at: CGPoint(x: front.maxX - front.width * 0.16, y: front.minY + front.height * 0.46))
            var stamp = c
            stamp.translateBy(x: front.maxX - front.width * 0.2, y: front.minY + front.height * 0.72)
            stamp.rotate(by: .degrees(-12))
            stamp.stroke(Path(roundedRect: CGRect(x: -30, y: -9, width: 60, height: 18), cornerRadius: 3),
                         with: .color(Color(hex: 0xD2463C).opacity(0.85)), lineWidth: 1.5)
            stamp.draw(Text("FRAGILE").font(.system(size: 10, weight: .heavy)).foregroundColor(Color(hex: 0xD2463C).opacity(0.85)),
                       at: .zero)
        }
    }
}
