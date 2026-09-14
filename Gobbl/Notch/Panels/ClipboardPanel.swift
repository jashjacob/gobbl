import GobblCore
import SwiftUI

/// Searchable clipboard history. Opened by ⇧⌘Space with the search field
/// focused; click (or Return on the first match) to copy and close.
struct ClipboardPanel: View {
    let state: NotchState
    @State private var clips = ClipboardModel.shared
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = clips.history.filtered(query)
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                    TextField("Search clipboard", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($searchFocused)
                        .onSubmit {
                            if let first = items.first { pick(first) }
                        }
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Palette.well))
                if !clips.history.items.isEmpty {
                    PillButton(title: "Clear", symbol: "trash") { clips.clearUnpinned() }
                        .help("Remove everything except pinned items")
                }
            }
            if items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 18, weight: .semibold))
                    Text(query.isEmpty ? "Copy something. Gob keeps your last \(ClipboardHistory.defaultLimit)." : "No matches")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            ClipRow(item: item) { pick(item) }
                        }
                    }
                }
            }
        }
        .onAppear { searchFocused = true }
    }

    private func pick(_ item: ClipItem) {
        clips.copy(item)
        state.window?.close()
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let action: () -> Void
    @State private var hovering = false
    private var clips: ClipboardModel { .shared }

    var body: some View {
        HStack(spacing: 9) {
            icon
                .frame(width: 26, height: 26)
            Text(item.preview)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if hovering || item.pinned {
                IconButton(symbol: item.pinned ? "pin.fill" : "pin", help: item.pinned ? "Unpin" : "Pin", size: 9.5,
                           tint: item.pinned ? Palette.accent : Palette.textTertiary) {
                    clips.togglePin(item)
                }
            }
            Text(item.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Palette.wellHover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .contextMenu {
            Button("Copy") { action() }
            Button(item.pinned ? "Unpin" : "Pin") { clips.togglePin(item) }
            if item.kind == .file {
                Button("Add to Shelf") {
                    ShelfModel.shared.add(item.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
                }
            }
            if item.kind == .link, let url = URL(string: item.text) {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Delete") { clips.remove(item) }
        }
        .help(item.sourceApp.map { "Copied from \($0)" } ?? "")
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            if let thumb = clips.thumbnail(for: item) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                symbol("photo")
            }
        case .file:
            let path = item.text.split(separator: "\n").first.map(String.init) ?? ""
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        case .link: symbol("link")
        case .text: symbol("text.alignleft")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.well))
    }
}
