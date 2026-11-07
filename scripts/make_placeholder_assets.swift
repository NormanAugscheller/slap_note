#!/usr/bin/env swift
// Generates the placeholder bitmaps SlapNote ships with until the real assets exist
// (see ASSETS_NEEDED.md). Run from the repository root:
//
//     swift scripts/make_placeholder_assets.swift
//
// It overwrites:
//   SlapNote/Resources/Assets.xcassets/AppIcon.appiconset/*.png (+ Contents.json)
//   SlapNote/Resources/paper_texture.png
// Replace those files with the real ones (same names and sizes) — no code changes needed.

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("SlapNote/Resources/Assets.xcassets/AppIcon.appiconset")
let texture = root.appendingPathComponent("SlapNote/Resources/paper_texture.png")

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "png", code: 1) }
    try data.write(to: url)
}

func bitmap(_ size: Int, gray: Bool = false, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: gray ? 1 : 4, hasAlpha: !gray, isPlanar: false,
                               colorSpaceName: gray ? .deviceWhite : .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Placeholder icon: a slightly rotated yellow note with a folded corner and a shadow.
func drawIcon(_ c: CGContext, size s: CGFloat) {
    c.clear(CGRect(x: 0, y: 0, width: s, height: s))
    c.translateBy(x: s / 2, y: s / 2)
    c.rotate(by: -4 * .pi / 180)
    let w = s * 0.68
    let note = CGRect(x: -w / 2, y: -w / 2, width: w, height: w)
    let fold = w * 0.2
    let body = CGMutablePath()
    body.move(to: CGPoint(x: note.minX, y: note.minY))
    body.addLine(to: CGPoint(x: note.maxX - fold, y: note.minY))
    body.addLine(to: CGPoint(x: note.maxX, y: note.minY + fold))
    body.addLine(to: CGPoint(x: note.maxX, y: note.maxY))
    body.addLine(to: CGPoint(x: note.minX, y: note.maxY))
    body.closeSubpath()
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.04, color: NSColor(white: 0, alpha: 0.35).cgColor)
    c.addPath(body)
    c.setFillColor(NSColor(srgbRed: 1, green: 0.945, blue: 0.478, alpha: 1).cgColor)
    c.fillPath()
    c.restoreGState()
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: note.maxX - fold, y: note.minY))
    flap.addLine(to: CGPoint(x: note.maxX - fold, y: note.minY + fold))
    flap.addLine(to: CGPoint(x: note.maxX, y: note.minY + fold))
    flap.closeSubpath()
    c.addPath(flap)
    c.setFillColor(NSColor(srgbRed: 0.86, green: 0.8, blue: 0.38, alpha: 1).cgColor)
    c.fillPath()
    c.setStrokeColor(NSColor(white: 0.2, alpha: 0.75).cgColor)
    c.setLineWidth(s * 0.022)
    c.setLineCap(.round)
    for i in 0..<3 {
        let y = note.maxY - w * (0.3 + CGFloat(i) * 0.18)
        let len = w * (i == 2 ? 0.4 : 0.62)
        c.move(to: CGPoint(x: note.minX + w * 0.16, y: y))
        c.addLine(to: CGPoint(x: note.minX + w * 0.16 + len, y: y))
    }
    c.strokePath()
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
let entries: [(String, Int, Int)] = [("16x16", 1, 16), ("16x16", 2, 32), ("32x32", 1, 32), ("32x32", 2, 64),
                                     ("128x128", 1, 128), ("128x128", 2, 256), ("256x256", 1, 256), ("256x256", 2, 512),
                                     ("512x512", 1, 512), ("512x512", 2, 1024)]
var images: [[String: String]] = []
for (size, scale, px) in entries {
    let name = "icon_\(size)\(scale == 2 ? "@2x" : "").png"
    let rep = bitmap(px) { drawIcon($0, size: CGFloat(px)) }
    try writePNG(rep, to: iconSet.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": size, "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))

// Tileable grayscale paper grain: per-pixel noise plus a few soft horizontal fibers (wrapping).
var rng = SystemRandomNumberGenerator()
let tex = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8,
                           samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                           colorSpaceName: .deviceWhite, bytesPerRow: 256, bitsPerPixel: 8)!
let pixels = tex.bitmapData!
for y in 0..<256 {
    for x in 0..<256 {
        let noise = Double(UInt8.random(in: 0...255, using: &rng)) / 255.0
        // sin(2πk·x/256) wraps exactly, so the texture tiles seamlessly.
        let fiber = sin(Double(y) * 2 * .pi * 9 / 256 + sin(Double(x) * 2 * .pi / 256) * 2) * 0.015
        let v = 0.92 + (noise - 0.5) * 0.09 + fiber
        pixels[y * 256 + x] = UInt8(min(max(v, 0), 1) * 255)
    }
}
try writePNG(tex, to: texture)
print("Placeholder assets written.")
