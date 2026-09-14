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

/// Gob as the Compact computer (centred at `c`, case width `w`), in a y-up
/// context: pastel case, CRT with a glowing lime face, floppy slot, feet.
func drawGob(_ ctx: CGContext, center c: CGPoint, width w: CGFloat, lookUp: Bool = true) {
    let h = w * 1.14
    let body = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    // Feet
    ctx.setFillColor(color(0xB9AE98))
    for side: CGFloat in [-1, 1] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: c.x + side * w * 0.3 - w * 0.1, y: body.minY - w * 0.045, width: w * 0.2, height: w * 0.07),
                           cornerWidth: w * 0.03, cornerHeight: w * 0.03, transform: nil))
        ctx.fillPath()
    }
    // Case
    let shell = CGPath(roundedRect: body, cornerWidth: w * 0.13, cornerHeight: w * 0.13, transform: nil)
    ctx.saveGState()
    ctx.addPath(shell)
    ctx.clip()
    let caseGradient = CGGradient(colorsSpace: sRGB, colors: [color(0xF6EFE3), color(0xD4C8B2)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(caseGradient, start: CGPoint(x: c.x, y: body.maxY), end: CGPoint(x: c.x, y: body.minY), options: [])
    ctx.restoreGState()
    ctx.addPath(shell)
    ctx.setStrokeColor(color(0xFFFFFF, 0.45))
    ctx.setLineWidth(w * 0.012)
    ctx.strokePath()
    // Recessed CRT
    let sw = w * 0.74, sh = h * 0.52
    let screen = CGRect(x: c.x - sw / 2, y: body.maxY - h * 0.09 - sh, width: sw, height: sh)
    ctx.addPath(CGPath(roundedRect: screen.insetBy(dx: -w * 0.035, dy: -w * 0.035), cornerWidth: w * 0.1, cornerHeight: w * 0.1, transform: nil))
    ctx.setFillColor(color(0xA89D86, 0.7))
    ctx.fillPath()
    let crt = CGPath(roundedRect: screen, cornerWidth: w * 0.08, cornerHeight: w * 0.08, transform: nil)
    ctx.saveGState()
    ctx.addPath(crt)
    ctx.clip()
    let crtGradient = CGGradient(colorsSpace: sRGB, colors: [color(0x1F3A28), color(0x0A120D)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(crtGradient, startCenter: CGPoint(x: screen.midX, y: screen.midY), startRadius: 0,
                           endCenter: CGPoint(x: screen.midX, y: screen.midY), endRadius: sw * 0.7, options: [])
    // Scanlines
    ctx.setFillColor(color(0x000000, 0.2))
    var y = screen.minY
    while y < screen.maxY { ctx.fill(CGRect(x: screen.minX, y: y, width: sw, height: w * 0.006)); y += w * 0.022 }
    ctx.restoreGState()
    // Glowing face
    let lime = color(0xA6F25C)
    let eyeY = screen.minY + sh * 0.6, dx = sw * 0.2, er = sw * 0.075
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: w * 0.05, color: lime)
    ctx.setFillColor(lime)
    for side: CGFloat in [-1, 1] {
        let ex = c.x + side * dx
        let ey = eyeY + (lookUp ? er * 0.3 : 0)
        ctx.addPath(CGPath(roundedRect: CGRect(x: ex - er * 0.75, y: ey - er, width: er * 1.5, height: er * 2),
                           cornerWidth: er * 0.35, cornerHeight: er * 0.35, transform: nil))
        ctx.fillPath()
    }
    ctx.setStrokeColor(lime)
    ctx.setLineWidth(w * 0.03)
    ctx.setLineCap(.round)
    let my = screen.minY + sh * 0.27
    ctx.move(to: CGPoint(x: c.x - sw * 0.12, y: my + sh * 0.02))
    ctx.addQuadCurve(to: CGPoint(x: c.x + sw * 0.12, y: my + sh * 0.02), control: CGPoint(x: c.x, y: my - sh * 0.12))
    ctx.strokePath()
    ctx.restoreGState()
    ctx.setFillColor(color(0xFF6FA5, 0.35))
    for side: CGFloat in [-1, 1] {
        ctx.fillEllipse(in: CGRect(x: c.x + side * dx * 1.6 - er, y: eyeY - er * 2.1, width: er * 2, height: er * 0.9))
    }
    // Chin: vents, floppy slot, drive light
    let slotY = body.minY + h * 0.2
    ctx.setFillColor(color(0x000000, 0.55))
    ctx.addPath(CGPath(roundedRect: CGRect(x: c.x - w * 0.02, y: slotY, width: w * 0.34, height: w * 0.04),
                       cornerWidth: w * 0.02, cornerHeight: w * 0.02, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(0x8F846E, 0.6))
    for i in 0..<3 {
        ctx.fill(CGRect(x: body.minX + w * 0.13 + CGFloat(i) * w * 0.05, y: slotY - h * 0.03, width: w * 0.02, height: h * 0.09))
    }
    ctx.setFillColor(lime)
    ctx.fill(CGRect(x: c.x + w * 0.25, y: slotY - h * 0.05, width: w * 0.05, height: w * 0.02))
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
    drawGob(ctx, center: CGPoint(x: 512, y: 490), width: 380)
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
