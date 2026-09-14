import SwiftUI

struct PillButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(prominent ? Color.black : Palette.text)
            .padding(.horizontal, 9).padding(.vertical, 4.5)
            .background(Capsule().fill(prominent ? Palette.accent : (hovering ? Palette.wellHover : Palette.well)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    var size: CGFloat = 11
    var tint: Color = Palette.textSecondary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovering ? Palette.text : tint)
                .frame(width: size * 2.4, height: size * 2.1)
                .background(Circle().fill(hovering ? Palette.wellHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Rounded well that groups a panel's content.
struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.well))
    }
}

// MARK: - Shape

/// Flush with the top edge of the screen, with concave flares where it meets
/// the menu bar (so it reads as part of the notch) and rounded bottom corners.
struct NotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat
    var attached: Bool

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard attached else {
            return Path(roundedRect: rect, cornerRadius: min(radius, rect.height / 2), style: .continuous)
        }
        let w = rect.width, h = rect.height
        let r = max(0, min(radius, (w - 2 * flare) / 2, h - flare))
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: flare, y: flare), control: CGPoint(x: flare, y: 0))
        p.addLine(to: CGPoint(x: flare, y: h - r))
        p.addQuadCurve(to: CGPoint(x: flare + r, y: h), control: CGPoint(x: flare, y: h))
        p.addLine(to: CGPoint(x: w - flare - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - flare, y: h - r), control: CGPoint(x: w - flare, y: h))
        p.addLine(to: CGPoint(x: w - flare, y: flare))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - flare, y: 0))
        p.closeSubpath()
        return p
    }
}
