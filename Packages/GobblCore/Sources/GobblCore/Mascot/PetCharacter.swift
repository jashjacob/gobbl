/// Which body the pet has. Both share every mood, hat and species colour;
/// only the drawing differs.
public enum PetCharacter: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The original squishy gumdrop with an antenna.
    case gob
    /// A little 80s desktop computer: face on its CRT screen, eats files through its floppy slot.
    case retro

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gob: "Blob"
        case .retro: "Retro computer"
        }
    }
}
