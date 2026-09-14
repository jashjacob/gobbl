import Foundation

/// A user-made look for the pet, shared as a small `.gobskin` JSON file:
///
///     { "format": 1, "id": "midnight", "name": "Midnight", "author": "@you",
///       "bodyTop": "#3A3F6B", "bodyBottom": "#1C1F3A",
///       "face": "#FFFFFF", "cheeks": "#FF6FA5", "glow": "#8FB3FF" }
///
/// Colours are "#RRGGBB". `face` is the eyes and mouth on the blob; `glow` is
/// the phosphor face on the retro computer. Anything missing falls back to the
/// species colours.
public struct PetSkin: Codable, Identifiable, Equatable, Hashable, Sendable {
    public static let fileExtension = "gobskin"
    public static let currentFormat = 1

    public var format: Int?
    public var id: String
    public var name: String
    public var author: String?
    public var bodyTop: String
    public var bodyBottom: String
    public var face: String?
    public var cheeks: String?
    public var glow: String?

    public init(id: String? = nil, name: String, author: String? = nil, bodyTop: String, bodyBottom: String,
                face: String? = nil, cheeks: String? = nil, glow: String? = nil) {
        format = Self.currentFormat
        self.id = id ?? Self.slug(name)
        self.name = name
        self.author = author
        self.bodyTop = bodyTop
        self.bodyBottom = bodyBottom
        self.face = face
        self.cheeks = cheeks
        self.glow = glow
    }

    public enum SkinError: Error, Equatable {
        case invalid(String)
    }

    /// 0–1 RGB from "#RRGGBB" (or "RRGGBB").
    public static func rgb(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    public static func hex(r: Double, g: Double, b: Double) -> String {
        func c(_ x: Double) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    /// Checks a skin from outside (a file someone shared) before it is used.
    public func validated() throws -> PetSkin {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw SkinError.invalid("The skin needs a name of up to 40 characters.") }
        guard Self.rgb(bodyTop) != nil, Self.rgb(bodyBottom) != nil else { throw SkinError.invalid("bodyTop and bodyBottom must be #RRGGBB colours.") }
        for (key, value) in [("face", face), ("cheeks", cheeks), ("glow", glow)] where value != nil && Self.rgb(value) == nil {
            throw SkinError.invalid("\(key) must be a #RRGGBB colour.")
        }
        if let format, format > Self.currentFormat { throw SkinError.invalid("This skin needs a newer version of Gobbl.") }
        var skin = self
        skin.name = trimmed
        skin.id = Self.slug(id.isEmpty ? trimmed : id)
        skin.author = author.map { String($0.prefix(40)) }
        return skin
    }

    public static func decode(_ data: Data) throws -> PetSkin {
        try JSONDecoder().decode(PetSkin.self, from: data).validated()
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    /// "Mint Chip!" → "mint-chip". Only [a-z0-9-], so it is a safe file name.
    public static func slug(_ s: String) -> String {
        let lowered = s.lowercased().map { ch -> Character in
            ch.isASCII && (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        let collapsed = String(lowered).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "skin" : String(collapsed.prefix(40))
    }

    public static let builtIn: [PetSkin] = [
        PetSkin(name: "Midnight", bodyTop: "#4A4F85", bodyBottom: "#1C1F3A", face: "#F4F6FF", cheeks: "#FF6FA5", glow: "#8FB3FF"),
        PetSkin(name: "Bubblegum", bodyTop: "#FFD1E8", bodyBottom: "#FF7EB9", glow: "#FF9ED0"),
        PetSkin(name: "Mint Chip", bodyTop: "#D2FAE3", bodyBottom: "#6FD39B", face: "#2B1B12"),
        PetSkin(name: "Terminal", bodyTop: "#3A3F38", bodyBottom: "#121411", face: "#A6F25C", cheeks: "#3E6B2A", glow: "#A6F25C"),
        PetSkin(name: "Sunset", bodyTop: "#FFD36E", bodyBottom: "#FF6F61", glow: "#FFB347"),
        PetSkin(name: "Classic Beige", bodyTop: "#F1E9D6", bodyBottom: "#CFC3A6", glow: "#A6F25C"),
    ]
}
