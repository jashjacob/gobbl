import CoreGraphics
import Testing
@testable import GobblCore

@Suite struct NotchGeometryTests {
    /// 14" MacBook Pro: 1512×982 points, 185 pt camera housing, 32 pt tall.
    let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
                                safeAreaTop: 32, auxiliaryLeftWidth: 663.5, auxiliaryRightWidth: 663.5)

    /// External display to the right of it, no notch, 25 pt menu bar.
    let external = ScreenMetrics(frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                                 visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415))

    @Test func notchIsDetectedAndCentred() {
        let g = NotchGeometry(metrics: notched)
        #expect(g.hasNotch)
        #expect(g.notchWidth == 185)
        #expect(g.barHeight == 32)
        #expect(g.centerX == 756)
        #expect(g.collapsedSize == CGSize(width: 185 + 128, height: 32))
    }

    @Test func notchShapeIsFlushWithTheTopOfTheScreen() {
        let g = NotchGeometry(metrics: notched)
        #expect(g.visibleRect(expanded: false).maxY == 982)
        #expect(g.visibleRect(expanded: true).maxY == 982)
        #expect(g.panelFrame.maxY == 982)
        #expect(g.panelFrame.midX == g.centerX)
    }

    @Test func externalDisplayGetsAPillUnderTheMenuBar() {
        let g = NotchGeometry(metrics: external)
        #expect(!g.hasNotch)
        #expect(g.barHeight == 25)
        #expect(g.centerX == 2792)                         // 1512 + 2560 / 2
        #expect(g.collapsedSize.height == NotchGeometry.pillHeight)
        #expect(g.visibleRect(expanded: false).maxY == 1409) // 1440 − 25 menu bar − 6 gap
    }

    @Test func expandedShapeFitsInsideThePanel() {
        for m in [notched, external] {
            let g = NotchGeometry(metrics: m)
            #expect(g.panelFrame.contains(g.visibleRect(expanded: true)))
            #expect(g.expandedSize.width > g.collapsedSize.width)
        }
    }

    @Test func hitTesting() {
        let g = NotchGeometry(metrics: notched)
        let wing = CGPoint(x: g.centerX - g.notchWidth / 2 - 20, y: 970)
        #expect(g.contains(wing, expanded: false))
        #expect(!g.contains(CGPoint(x: 100, y: 970), expanded: false))
        // Below the collapsed band but inside the expanded panel.
        let below = CGPoint(x: g.centerX, y: 982 - 100)
        #expect(!g.contains(below, expanded: false))
        #expect(g.contains(below, expanded: true))
    }
}
