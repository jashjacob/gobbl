import AppKit
import GobblCore
import Observation
import SwiftUI

/// Built-in and user-made skins. Custom ones live as `.gobskin` files in
/// ~/Library/Application Support/Gobbl/Skins; new ones arrive by dropping a
/// file on the notch, double-clicking it, or making one in Settings.
@MainActor @Observable
final class SkinLibrary {
    static let shared = SkinLibrary()

    private(set) var custom: [PetSkin] = []

    static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gobbl/Skins", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() { reload() }

    var all: [PetSkin] { PetSkin.builtIn + custom }

    func skin(id: String?) -> PetSkin? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    func isCustom(_ skin: PetSkin) -> Bool { custom.contains(skin) }

    /// Validates and saves a skin; replaces a custom one with the same id.
    @discardableResult
    func save(_ skin: PetSkin) throws -> PetSkin {
        var skin = try skin.validated()
        if PetSkin.builtIn.contains(where: { $0.id == skin.id }) { skin.id += "-custom" }
        try skin.encoded().write(to: Self.folder.appendingPathComponent(skin.id).appendingPathExtension(PetSkin.fileExtension),
                                 options: .atomic)
        reload()
        return skin
    }

    /// Installs a shared file and puts it on the pet.
    @discardableResult
    func install(from url: URL) -> Bool {
        do {
            let skin = try save(PetSkin.decode(Data(contentsOf: url)))
            PetModel.shared.skinID = skin.id
            PetModel.shared.send(.celebrate)
            HUDModel.shared.show(.init(symbol: "paintpalette.fill", label: String(skin.name.prefix(12)), tint: Palette.accent), for: 3)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Gob can't wear “\(url.lastPathComponent)”"
            if case PetSkin.SkinError.invalid(let why) = error { alert.informativeText = why } else { alert.informativeText = error.localizedDescription }
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return false
        }
    }

    func remove(_ skin: PetSkin) {
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(skin.id).appendingPathExtension(PetSkin.fileExtension))
        if PetModel.shared.skinID == skin.id { PetModel.shared.skinID = nil }
        reload()
    }

    /// Writes the skin to Downloads and offers the share menu.
    func share(_ skin: PetSkin) {
        do {
            let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let url = try ClipStudio.unique(folder.appendingPathComponent(skin.name).appendingPathExtension(PetSkin.fileExtension))
            try skin.encoded().write(to: url)
            Share.show([url])
            HUDModel.shared.show(.init(symbol: "paintpalette.fill", label: "Saved", tint: Palette.accent), for: 2)
        } catch {
            NSSound.beep()
        }
    }

    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        custom = files.filter { $0.pathExtension == PetSkin.fileExtension }
            .compactMap { try? PetSkin.decode(Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension Color {
    init?(skinHex: String?) {
        guard let c = PetSkin.rgb(skinHex) else { return nil }
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    /// "#RRGGBB" for the skin editor.
    var skinHex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return PetSkin.hex(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
    }
}

/// Settings sheet: pick colours, see both characters live, save and share.
struct SkinEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pet = PetModel.shared
    @State private var name = "My Gob"
    @State private var top = Color(skinHex: "#B8F28A")!
    @State private var bottom = Color(skinHex: "#5BB84A")!
    @State private var face = Color(skinHex: "#16161A")!
    @State private var cheeks = Color(skinHex: "#FF6FA5")!
    @State private var glow = Color(skinHex: "#A6F25C")!
    @State private var error: String?

    private var skin: PetSkin {
        PetSkin(name: name, author: nil, bodyTop: top.skinHex, bodyBottom: bottom.skinHex,
                face: face.skinHex, cheeks: cheeks.skinHex, glow: glow.skinHex)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Make a Skin").font(.headline)
            HStack(spacing: 18) {
                ForEach(PetCharacter.allCases) { character in
                    GobView(mood: .happy, genome: pet.genome, stage: pet.stats.stage, size: 88, hat: pet.hat,
                            character: character, skin: skin)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.black))
                }
            }
            Form {
                TextField("Name", text: $name)
                ColorPicker("Case top", selection: $top, supportsOpacity: false)
                ColorPicker("Case bottom", selection: $bottom, supportsOpacity: false)
                ColorPicker("Screen glow", selection: $glow, supportsOpacity: false)
                ColorPicker("Cheeks", selection: $cheeks, supportsOpacity: false)
            }
            .formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save & Share…") { save(share: true) }
                Button("Save") { save(share: false) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func save(share: Bool) {
        do {
            let saved = try SkinLibrary.shared.save(skin)
            pet.skinID = saved.id
            if share { SkinLibrary.shared.share(saved) }
            dismiss()
        } catch PetSkin.SkinError.invalid(let why) {
            error = why
        } catch {
            self.error = error.localizedDescription
        }
    }
}
