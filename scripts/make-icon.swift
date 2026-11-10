// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024
    // Squircle tile
    let tile = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.09, blue: 0.16, alpha: 1), NSColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1)])!
        .draw(in: tile, angle: -90)
    tile.addClip()
    // Ambient glow
    let glowColors = [NSColor(red: 1, green: 0.45, blue: 0.2, alpha: 0.55), NSColor(red: 0.85, green: 0.2, blue: 0.75, alpha: 0.45),
                      NSColor(red: 0.2, green: 0.7, blue: 1, alpha: 0.5)]
    for (i, c) in glowColors.enumerated() {
        let r = 330 * s
        let cx = (300 + CGFloat(i) * 210) * s
        let g = NSGradient(colors: [c, c.withAlphaComponent(0)])!
        g.draw(fromCenter: NSPoint(x: cx, y: 560 * s), radius: 0, toCenter: NSPoint(x: cx, y: 560 * s), radius: r, options: [])
    }
    // Light bar
    let bar = NSBezierPath(roundedRect: NSRect(x: 230 * s, y: 380 * s, width: 564 * s, height: 64 * s), xRadius: 32 * s, yRadius: 32 * s)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 70 * s, color: NSColor(red: 1, green: 0.55, blue: 0.4, alpha: 1).cgColor)
    NSGradient(colors: [NSColor(red: 1, green: 0.55, blue: 0.15, alpha: 1), NSColor(red: 1, green: 0.3, blue: 0.6, alpha: 1),
                        NSColor(red: 0.55, green: 0.35, blue: 1, alpha: 1), NSColor(red: 0.2, green: 0.8, blue: 1, alpha: 1)])!
        .draw(in: bar, angle: 0)
    ctx.restoreGState()
    // Glass highlight
    let hl = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 560 * s, width: 824 * s, height: 364 * s), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!.draw(in: hl, angle: -90)
    img.unlockFocus()
    return img
}

let fm = FileManager.default
let set = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let rep = NSBitmapImageRep(data: render(px).tiffRepresentation!)!
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try! render(1024).tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }!
    .write(to: URL(fileURLWithPath: "docs/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/icon.png")
