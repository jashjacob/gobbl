#!/usr/bin/env swift
// Draws Gobbl's app icon — Gob peeking out from under a notch — and the site
// images, with plain CoreGraphics so the art has no dependencies.
//
// Usage: swift scripts/make-icon.swift   (from the repo root)
// Writes Gobbl/Assets.xcassets/AppIcon.appiconset/*, site/img/icon.png, site/img/og.png

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let lime = NSColor(srgbRed: 0.65, green: 0.95, blue: 0.36, alpha: 1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Gob, centred at `c` with body width `w`, in a y-up context.
func drawGob(_ ctx: CGContext, center c: CGPoint, width w: CGFloat, lookUp: Bool = true) {
    let h = w * 0.78
    let body = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    // Antenna
    ctx.setStrokeColor(color(0x5FAE2E))
    ctx.setLineWidth(w * 0.035)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: c.x, y: body.maxY - 2))
    ctx.addQuadCurve(to: CGPoint(x: c.x + w * 0.08, y: body.maxY + w * 0.17), control: CGPoint(x: c.x - w * 0.03, y: body.maxY + w * 0.1))
    ctx.strokePath()
    let r = w * 0.055
    ctx.setFillColor(color(0xC8FF8A))
    ctx.fillEllipse(in: CGRect(x: c.x + w * 0.08 - r, y: body.maxY + w * 0.17 - r, width: r * 2, height: r * 2))
    // Body
    let path = CGPath(roundedRect: body, cornerWidth: w * 0.5, cornerHeight: h * 0.62, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0xC6FF8E), color(0x6CC23A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: c.x, y: body.maxY), end: CGPoint(x: c.x, y: body.minY), options: [])
    ctx.setFillColor(color(0xFFFFFF, 0.35))
    ctx.fillEllipse(in: CGRect(x: body.minX + w * 0.16, y: body.maxY - h * 0.28, width: w * 0.26, height: h * 0.16))
    ctx.restoreGState()
    // Eyes
    let eyeY = body.minY + h * 0.56, dx = w * 0.19, er = w * 0.085
    for side: CGFloat in [-1, 1] {
        let ex = c.x + side * dx
        ctx.setFillColor(color(0x16161A))
        ctx.fillEllipse(in: CGRect(x: ex - er * 0.75, y: eyeY - er, width: er * 1.5, height: er * 2))
        ctx.setFillColor(color(0xFFFFFF))
        let g = er * 0.55
        ctx.fillEllipse(in: CGRect(x: ex - er * 0.45, y: eyeY + (lookUp ? er * 0.25 : 0), width: g, height: g))
        // Cheeks
        ctx.setFillColor(color(0xFF6FA5, 0.4))
        ctx.fillEllipse(in: CGRect(x: c.x + side * dx * 1.6 - er, y: eyeY - er * 1.9, width: er * 2, height: er * 1.1))
    }
    // Smile
    ctx.setStrokeColor(color(0x16161A))
    ctx.setLineWidth(w * 0.035)
    ctx.move(to: CGPoint(x: c.x - w * 0.1, y: body.minY + h * 0.3))
    ctx.addQuadCurve(to: CGPoint(x: c.x + w * 0.1, y: body.minY + h * 0.3), control: CGPoint(x: c.x, y: body.minY + h * 0.18))
    ctx.strokePath()
}

func bitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

/// The 1024 master: macOS icon grid (824 pt squircle inset 100 pt), dark tile,
/// a notch cut into the top edge, Gob peeking out underneath.
func icon(_ ctx: CGContext, size s: CGFloat) {
    let k = s / 1024
    ctx.scaleBy(x: k, y: k)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x15171C))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [color(0x2A2F38), color(0x0E1013)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Lime glow behind Gob
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0xA6F25C, 0.35), color(0xA6F25C, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 360, options: [])
    // The notch: a black bar hanging from the top edge with rounded bottom corners.
    let notch = CGRect(x: 512 - 190, y: 924 - 150, width: 380, height: 170)
    ctx.addPath(CGPath(roundedRect: notch, cornerWidth: 60, cornerHeight: 60, transform: nil))
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
    ctx.fill(CGRect(x: notch.minX, y: notch.midY, width: notch.width, height: notch.height))
    drawGob(ctx, center: CGPoint(x: 512, y: 520), width: 460)
    ctx.restoreGState()
    // Hairline edge
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.08))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

// App icon set
let set = root.appendingPathComponent("Gobbl/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try bitmap(px, px) { icon($0, size: CGFloat(px)) }.write(to: set.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appendingPathComponent("Contents.json"))
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.write(
    to: root.appendingPathComponent("Gobbl/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)

// Site images
let img = root.appendingPathComponent("site/img")
try FileManager.default.createDirectory(at: img, withIntermediateDirectories: true)
try bitmap(512, 512) { icon($0, size: 512) }.write(to: img.appendingPathComponent("icon.png"))

// Open Graph card, 1200×630: icon left, headline right.
let og = bitmap(1200, 630) { ctx in
    ctx.setFillColor(color(0x0B0B0E))
    ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 630))
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0xA6F25C, 0.22), color(0xA6F25C, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 315), startRadius: 0,
                           endCenter: CGPoint(x: 300, y: 315), endRadius: 420, options: [])
    ctx.saveGState()
    ctx.translateBy(x: 50, y: 65)
    icon(ctx, size: 500)
    ctx.restoreGState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let title = NSAttributedString(string: "Your notch\nhas a pet.", attributes: [
        .font: NSFont.systemFont(ofSize: 84, weight: .heavy), .foregroundColor: NSColor.white])
    title.draw(in: CGRect(x: 580, y: 250, width: 600, height: 230))
    let sub = NSAttributedString(string: "Gobbl · free & open source for Mac", attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: lime])
    sub.draw(at: CGPoint(x: 584, y: 190))
    NSGraphicsContext.current = nil
}
try og.write(to: img.appendingPathComponent("og.png"))
print("Wrote \(set.path), site/img/icon.png, site/img/og.png")
