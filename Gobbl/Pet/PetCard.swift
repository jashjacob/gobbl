import AppKit
import GobblCore
import SwiftUI

/// The shareable pet card: a 1080×1080 PNG with Gob, species, rarity, level
/// and lifetime stats, saved to Downloads and offered through the share menu.
@MainActor
enum PetCard {
    static func share() {
        guard let url = render() else { return }
        PetModel.shared.send(.celebrate)
        HUDModel.shared.show(.init(symbol: "photo.fill", label: "Saved", tint: Palette.accent), for: 2)
        Share.show([url])
    }

    /// Renders to ~/Downloads; returns the file.
    @discardableResult
    static func render(to folder: URL? = nil) -> URL? {
        let pet = PetModel.shared
        let renderer = ImageRenderer(content: PetCardView(name: pet.name, genome: pet.genome, stats: pet.stats, hat: pet.hat))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let dir = folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("\(pet.name) the \(pet.genome.species.displayName).png")
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

struct PetCardView: View {
    let name: String
    let genome: PetGenome
    let stats: MascotStats
    var hat: Hat = .none

    private var hue: Double { genome.species.hue }

    var body: some View {
        ZStack {
            Color(hex: 0x0B0B0E)
            RadialGradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 0.9).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: 330)
            VStack(spacing: 0) {
                HStack {
                    Text("GOBBL").font(.system(size: 15, weight: .heavy, design: .rounded)).kerning(3)
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    RarityChip(rarity: genome.rarity, shiny: genome.shiny)
                }
                Spacer(minLength: 0)
                GobView(mood: .happy, genome: genome, stage: stats.stage, size: 230, hat: hat, frozen: true)
                Text(name)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                Text("\(genome.shiny ? "Shiny " : "")\(genome.species.displayName) · Level \(stats.level)")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hue: hue, saturation: 0.45, brightness: 1))
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    stat("\(stats.filesGobbled)", "files gobbled")
                    stat("\(stats.burps)", "burps")
                    stat("\(stats.pets)", "pets")
                    stat("\(stats.longestStreak)", "day streak")
                    stat("\(daysTogether)", daysTogether == 1 ? "day together" : "days together")
                }
                Text("Your notch has a pet · gobbl.xeve.io")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 18)
            }
            .padding(34)
        }
        .frame(width: 540, height: 540)
        .environment(\.colorScheme, .dark)
    }

    private var daysTogether: Int {
        guard let hatched = stats.hatched else { return 1 }
        return max(1, (Calendar.current.dateComponents([.day], from: hatched, to: Date()).day ?? 0) + 1)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
    }
}

struct RarityChip: View {
    let rarity: Rarity
    let shiny: Bool

    var body: some View {
        HStack(spacing: 5) {
            if shiny { Text("✦") }
            Text(rarity.rawValue.uppercased())
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .kerning(1.5)
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    private var color: Color {
        switch rarity {
        case .common: Color(hex: 0xB8BCC6)
        case .uncommon: Palette.accent
        case .rare: Color(hex: 0x5B9CF6)
        case .legendary: Palette.gold
        }
    }
}
