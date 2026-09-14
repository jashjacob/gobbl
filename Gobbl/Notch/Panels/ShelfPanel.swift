import GobblCore
import SwiftUI

struct ShelfPanel: View {
    let dropTargeted: Bool
    @State private var shelf = ShelfModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Shelf").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                Text("\(shelf.items.count)").font(.mono(11)).foregroundStyle(Palette.textTertiary)
                Spacer()
                if !shelf.items.isEmpty {
                    PillButton(title: "AirDrop", symbol: "airplayaudio") { shelf.airDrop(shelf.items) }
                    PillButton(title: "Share", symbol: "square.and.arrow.up") { shelf.share(shelf.items) }
                    PillButton(title: "Clear", symbol: "xmark") { shelf.removeAll() }
                }
            }
            if shelf.items.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(dropTargeted ? Palette.accent : Palette.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line").font(.system(size: 16, weight: .semibold))
                            Text(dropTargeted ? "Let go. Gob's got it." : "Drop files here. Gob is hungry.")
                                .font(.system(size: 11.5))
                        }
                        .foregroundStyle(dropTargeted ? Palette.accent : Palette.textSecondary)
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(shelf.items) { ShelfTile(item: $0) }
                    }
                }
                .overlay {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @State private var hovering = false
    private var shelf: ShelfModel { .shared }

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: shelf.icon(for: item))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Palette.wellHover : Palette.well))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag {
            PetModel.shared.send(.filesDraggedOut)
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Quick Look") { shelf.quickLook(item) }
            Button("Show in Finder") { shelf.reveal([item]) }
            Divider()
            FileActionsMenu(items: [item])
            Divider()
            Button("AirDrop") { shelf.airDrop([item]) }
            Button("Share…") { shelf.share([item]) }
            Button("Copy Path") { shelf.copyPath(item) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}
