import CoreGraphics

/// What NotchGeometry needs to know about a screen, decoupled from NSScreen
/// so the layout maths is testable. All rects are in global screen space.
public struct ScreenMetrics: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// `safeAreaInsets.top`: non-zero only on displays with a camera housing.
    public var safeAreaTop: CGFloat
    /// Widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
    public var auxiliaryLeftWidth: CGFloat?
    public var auxiliaryRightWidth: CGFloat?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat = 0,
                auxiliaryLeftWidth: CGFloat? = nil, auxiliaryRightWidth: CGFloat? = nil) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
    }
}

/// Layout of the notch overlay on one screen. On a notched display the shape
/// hugs the camera housing with a "wing" either side; elsewhere it is a pill
/// floating just under the menu bar.
public struct NotchGeometry: Equatable, Sendable {
    /// Concave flare where the shape meets the top edge of the screen.
    public static let flare: CGFloat = 8
    public static let pillHeight: CGFloat = 30

    public var hasNotch = false
    public var notchWidth: CGFloat = 0
    /// Menu bar / notch height.
    public var barHeight: CGFloat = 24
    /// Width of each wing beside the notch.
    public var wing: CGFloat = 64
    /// Horizontal centre of the notch (or of the screen), global coordinates.
    public var centerX: CGFloat = 0
    public var screenTop: CGFloat = 0
    public var expandedWidth: CGFloat = 560
    public var expandedContentHeight: CGFloat = 192

    public init() {}

    public init(metrics m: ScreenMetrics, wing: CGFloat = 64) {
        self.wing = wing
        screenTop = m.frame.maxY
        centerX = m.frame.midX
        if m.safeAreaTop > 0, let left = m.auxiliaryLeftWidth, let right = m.auxiliaryRightWidth {
            hasNotch = true
            notchWidth = max(0, m.frame.width - left - right)
            barHeight = m.safeAreaTop
            // Widths only, so this holds whether the aux areas are screen-local or global.
            centerX = m.frame.minX + left + notchWidth / 2
        } else {
            barHeight = max(24, m.frame.maxY - m.visibleFrame.maxY)
        }
    }

    /// Height of the always-visible band (the collapsed shape).
    public var headerHeight: CGFloat { hasNotch ? barHeight : Self.pillHeight }

    public var collapsedSize: CGSize {
        hasNotch ? CGSize(width: notchWidth + 2 * wing, height: barHeight)
                 : CGSize(width: 2 * wing + 24, height: Self.pillHeight)
    }

    public var expandedSize: CGSize {
        CGSize(width: max(expandedWidth, collapsedSize.width + 24), height: headerHeight + expandedContentHeight)
    }

    /// Panel size: room for the expanded shape, its flares and its shadow.
    public var canvas: CGSize {
        CGSize(width: expandedSize.width + 2 * Self.flare + 60, height: expandedSize.height + 40)
    }

    /// Top edge of the visible shape: flush with the screen top on a notch,
    /// just below the menu bar otherwise.
    public var shapeTop: CGFloat { hasNotch ? screenTop : screenTop - barHeight - 6 }

    public var panelFrame: CGRect {
        CGRect(x: centerX - canvas.width / 2, y: shapeTop - canvas.height, width: canvas.width, height: canvas.height)
    }

    /// The visible shape in global screen coordinates.
    public func visibleRect(expanded: Bool) -> CGRect {
        let size = expanded ? expandedSize : collapsedSize
        return CGRect(x: centerX - size.width / 2, y: shapeTop - size.height, width: size.width, height: size.height)
    }

    public func contains(_ point: CGPoint, expanded: Bool, slop: CGFloat = 4) -> Bool {
        visibleRect(expanded: expanded).insetBy(dx: -slop, dy: -slop).contains(point)
    }
}
